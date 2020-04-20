#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

registre_bkp_vault() {
	STACK_ID=$(docker stack ps ${OCARIOT_STACK_NAME} --format "{{.ID}}" --filter "name=${OCARIOT_STACK_NAME}_vault" --filter "desired-state=running")
	CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
	echo "Executando script $2 para: $1"
	docker exec -t ${CONTAINER_ID} vault kv patch secret/map-accessor-token bkp_realized=true
}

set_variables_environment "${ENV_OCARIOT}"

backup_container_operation stop &> /dev/null

BACKEND_VAULT="consul"

VALIDATING_OPTS=$(echo "$@" | sed 's/ /\n/g' |
	grep -P "(\-\-services|\-\-time|\-\-expression|\-\-keys).*" -v | grep '\-\-')

CHECK_NAME_SERVICE_OPT=$(echo "$@" | grep -wo '\-\-services')
SERVICES=$(echo "$@" | grep -o -P '(?<=--services ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_TIME_OPT=$(echo "$@" | grep -wo '\-\-time')
RESTORE_TIME=$(echo "$@" | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

CHECK_AUTO_BKP_OPT=$(echo "$@" | grep -wo '\-\-expression')
EXPRESSION_BKP=$(echo "$@" | grep -o -P '(?<=--expression ).*' | sed 's/--.*//g')

CHECK_KEY_OPT=$(echo "$@" | grep -wo '\-\-keys')
KEY_DIRECTORY=$(echo "$@" | grep -o -P '(?<=--keys ).*' | sed "s/--.*//g")

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) ||
	([ "$2" != "--services" ] && [ "$2" != "--time" ] && [ "$2" != "--keys" ] &&
		[ "$2" != "--expression" ] && [ "$2" != "--path" ] && [ "$2" != "" ]) ||
	[ ${VALIDATING_OPTS} ] ||
	([ ${CHECK_NAME_SERVICE_OPT} ] && [ "${SERVICES}" = "" ]) ||
	([ ${CHECK_KEY_OPT} ] && [ "$(validate_file_path ${KEY_DIRECTORY})" ]) ||
	([ ${CHECK_AUTO_BKP_OPT} ] && [ "${EXPRESSION_BKP}" = "" ]) ||
	([ ${CHECK_TIME_OPT} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
	stack_help
fi

if ([ $1 = "backup" ] && [ ${CHECK_TIME_OPT} ]) ||
	([ $1 = "restore" ] && [ ${CHECK_AUTO_BKP_OPT} ]); then
	stack_help
fi

check_backup_target_config "${OCARIOT_CREDS_DRIVER}"

if [ ${RESTORE_TIME} ]; then
	RESTORE_TIME="--time ${RESTORE_TIME}"
fi

COMMAND="backupFull"
BACKUP_VOLUME_PROPERTY=""
SOURCE_VOLUME_PROPERTY=":ro"

if [ "$1" = "restore" ]; then
	if [ ${CHECK_KEY_OPT} ]; then
		cp ${KEY_DIRECTORY} ${INSTALL_PATH}/config/ocariot/vault/.keys
		echo "Keys restored with success!"
	fi
	COMMAND="restore ${RESTORE_TIME}"
	BACKUP_VOLUME_PROPERTY=":ro"
	SOURCE_VOLUME_PROPERTY=""

	check_restore_target_config
fi

if [ ${CHECK_AUTO_BKP_OPT} ]; then

	CRONTAB_COMMAND="${EXPRESSION_BKP} ${INSTALL_PATH}/ocariot stack backup ${CHECK_NAME_SERVICE_OPT} ${SERVICES} >> /tmp/ocariot_backup.log"

	STATUS=$(check_crontab "${CRONTAB_COMMAND}")

	if [ "${STATUS}" = "enable" ]; then
		crontab -u ${USER} -l
		echo "Backup is already scheduled"
		exit
	fi
	(
		crontab -u ${USER} -l
		echo "${CRONTAB_COMMAND}"
	) | crontab -u ${USER} -

	STATUS=$(check_crontab "${CRONTAB_COMMAND}")

	if [ "${STATUS}" = "enable" ]; then
		crontab -u ${USER} -l
		echo "Backup schedule successful!"
	else
		echo "Unsuccessful backup schedule!"
	fi
	exit
fi

VOLUMES_BKP=""
RUNNING_SERVICES=""

OCARIOT_VOLUMES=$(cat ${INSTALL_PATH}/docker-ocariot-stack.yml | grep -P "name: ocariot.*data" | sed 's/\(name:\| \)//g')
EXPRESSION_GREP=$(echo ${OCARIOT_VOLUMES} | sed 's/ /|/g')

# Verifying if backup exist
if [ "$1" = "restore" ] && [ "${RESTORE_TARGET}" = "LOCAL" ]; then
	DIRECTORIES=$(ls ${LOCAL_TARGET} 2>/dev/null)
	if [ $? -ne 0 ]; then
		echo "Directory ${LOCAL_TARGET} not found."
		exit
	fi

	EXIST_BKP=false
	for DIRECTORY in ${DIRECTORIES}; do
		if [ "$(echo "${OCARIOT_VOLUMES}" | grep -w "${DIRECTORY}")" ]; then
			EXIST_BKP=true
			break
		fi
	done

	if ! ${EXIST_BKP}; then
		echo "No container backup was found"
		exit
	fi
fi

VOLUME_COMMAND="list --verbosity=9"

if [ -z "${SERVICES}" ]; then
	if [ "$1" = "restore" ] && [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		SERVICES=$(ls ${LOCAL_TARGET} |
			grep -oE "${EXPRESSION_GREP}" |
			sed 's/\(psmdb-\|psmysql-\|ocariot-\|-data\|redis-\)//g')
	elif [ "$1" = "restore" ] && [ "${RESTORE_TARGET}" != "LOCAL" ]; then
		SERVICES=$(cloud_bkps "" "${OCARIOT_CREDS_DRIVER}" ${VOLUME_COMMAND} |
			grep -oE "${EXPRESSION_GREP}" |
			sed 's/\(psmdb-\|psmysql-\|ocariot-\|-data\|redis-\)//g')
	else
		SERVICES=$(docker volume ls --format "{{.Name}}" |
			grep -oE "${EXPRESSION_GREP}" |
			sed 's/\(psmdb-\|psmysql-\|ocariot-\|-data\|redis-\)//g')
	fi
fi
SERVICES=$(echo ${SERVICES} | tr " " "\n" | sed "s/vault/${BACKEND_VAULT}/g" | sort -u)

for SERVICE in ${SERVICES}; do
	FULL_NAME_SERVICE=$(docker stack services ${OCARIOT_STACK_NAME} --format={{.Name}} 2>/dev/null |
		grep -w ${OCARIOT_STACK_NAME}_.*${SERVICE})
	RUNNING_SERVICES="${RUNNING_SERVICES} ${FULL_NAME_SERVICE}"

	if [ "$1" = "restore" ] && [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		MESSAGE="Not found ${SERVICE} volume!"
		VOLUME_NAME=$(ls ${LOCAL_TARGET} |
			grep -oE "${EXPRESSION_GREP}" |
			grep -w ${SERVICE})
	elif [ "$1" = "restore" ] && [ "${RESTORE_TARGET}" != "LOCAL" ]; then
		if [ -z "${CLOUD_BACKUPS}" ];then
			CLOUD_BACKUPS=$(cloud_bkps "" "${OCARIOT_CREDS_DRIVER}" ${VOLUME_COMMAND})
		fi
		MESSAGE="Volume BKP ${SERVICE} not found!"
		VOLUME_NAME="$(echo ${CLOUD_BACKUPS} |
			grep -oE "${EXPRESSION_GREP}" |
			grep -w ${SERVICE})"
	else
		MESSAGE="Volume BKP ${SERVICE} not found!"
		VOLUME_NAME=$(docker volume ls \
			--format "{{.Name}}" |
			grep -oE "${EXPRESSION_GREP}" |
			grep -w ${SERVICE})
	fi

	if [ -z "${VOLUME_NAME}" ]; then
		echo "${MESSAGE}"
		exit
	fi
	VOLUMES_BKP="${VOLUMES_BKP} ${VOLUME_NAME}"
done

VOLUMES_BKP=$(echo "${VOLUMES_BKP}" | sed 's/ /\n/g' | sort -u)

if [ -z "${VOLUMES_BKP}" ]; then
	echo "Not found ${OCARIOT_STACK_NAME} volumes!"
	exit
fi

if [ "$(echo ${RUNNING_SERVICES} | grep ${BACKEND_VAULT})" ]; then
	RUNNING_SERVICES="${RUNNING_SERVICES} ${OCARIOT_STACK_NAME}_vault"
	registre_bkp_vault >/dev/null
fi

remove_services "${RUNNING_SERVICES}"

if [ "$1" = "restore" ]; then
	remove_volumes "${VOLUMES_BKP}"
fi

INCREMENT=1
for VOLUME in ${VOLUMES_BKP}; do
	VOLUMES="${VOLUMES} -v ${VOLUME}:/source/${VOLUME}${SOURCE_VOLUME_PROPERTY}"
	VOLUMES_CACHE="${VOLUMES_CACHE} -v cache-${VOLUME}:/volumerize-cache/${VOLUME}"
	INCREMENT=$((INCREMENT + 1))
done

PROCESS_BKP="OK"
BKP_CONFIG_MODEL=$(mktemp --suffix=.json)

docker run -d --rm \
	--name ${BACKUP_CONTAINER_NAME} \
	${VOLUMES} \
	${VOLUMES_CACHE} \
	-v ${LOCAL_TARGET}:/local-backup${BACKUP_VOLUME_PROPERTY} \
	-v ${OCARIOT_CREDS_DRIVER}:/credentials \
	-v ${BKP_CONFIG_MODEL}:/etc/volumerize/multiconfig.json:rw \
	blacklabelops/volumerize &> /dev/null

if [ -z "${BACKUP_DATA_RETENTION}" ]; then
	BACKUP_DATA_RETENTION="15D"
fi

INCREMENT=1
for VOLUME in ${VOLUMES_BKP}; do
	if [ "$1" = "backup" ]; then
		multi_backup_config "${BKP_CONFIG_MODEL}" "${VOLUME}"
	else
		restore_config "${BKP_CONFIG_MODEL}" "${VOLUME}"
	fi

	backup_container_operation restart

	echo "======Backup of ${VOLUME} volume======"

	docker exec -t \
		-e VOLUMERIZE_CACHE=/volumerize-cache/${VOLUME} \
		-e VOLUMERIZE_SOURCE=/source/${VOLUME} \
		-e VOLUMERIZE_TARGET="multi:///etc/volumerize/multiconfig.json?mode=mirror&onfail=abort" \
		-e GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID} \
		-e GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY} \
		-e AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID} \
		-e AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY} \
		${BACKUP_CONTAINER_NAME} bash -c "${COMMAND} && remove-older-than ${BACKUP_DATA_RETENTION} --force"

	if [ $? != 0 ]; then
		PROCESS_BKP=FALSE
		echo "Error during $1 operation"
		exit 1
	fi
	INCREMENT=$((INCREMENT + 1))
done

backup_container_operation stop

if [ "${PROCESS_BKP}" = "OK" ]; then
	RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g')

	if [ "${RUNNING_SERVICES}" ]; then
		${INSTALL_PATH}/scripts/stack/start.sh
	fi
fi
