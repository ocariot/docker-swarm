#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

check_crontab() {
	RET_CRONTAB_COMMAND=$(crontab -u "${USER}" -l | grep -F "$1")

	if [ "${RET_CRONTAB_COMMAND}" ]; then
		echo "enable"
	else
		echo "disable"
	fi
}

remove_volumes() {
	for VOLUME_NAME in $1; do

		VOLUME=$(docker volume ls --filter "name=${VOLUME_NAME}" --format {{.Name}})

		if [ -z "${VOLUME}" ]; then
			continue
		fi

		RET=1
		printf "Removing Volume: %s" "${VOLUME_NAME}"
		while [[ ${RET} -ne 0 ]]; do
			printf "."
			docker volume rm ${VOLUME_NAME} -f &>/dev/null
			RET=$?
		done
		printf "\n"
	done
}

validate_file_path() {
	ls $1 &>/dev/null
	if [ $? != 0 ] || [ -z "$1" ]; then
		echo "Path $1 not found!"
	fi
}

registre_bkp_vault() {
	STACK_ID=$(docker stack ps ${OCARIOT_STACK_NAME} --format "{{.ID}}" --filter "name=${OCARIOT_STACK_NAME}_vault" --filter "desired-state=running")
	CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
	echo "Executando script $2 para: $1"
	docker exec -t ${CONTAINER_ID} vault kv patch secret/map-accessor-token bkp_realized=true
}

cloud_bkps() {
	docker run -it --rm --name ${BACKUP_CONTAINER_NAME} \
		-v google_credentials:/credentials \
		-e "VOLUMERIZE_SOURCE=/source" \
		-e "VOLUMERIZE_TARGET=${CLOUD_TARGET}" \
		-e "GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY}" \
		-e "AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY}" \
		blacklabelops/volumerize "$@"
}

validate_bkp_target() {
	if [ -z "$(echo $1 | grep -P "$2")" ]; then
		echo "$3"
		exit
	fi
}

check_restore_target_config() {
	ERROR_MESSAGE="The CLOUD_TARGET variable does not correspond to the RESTORE_TARGET variable."

	case ${RESTORE_TARGET} in
	LOCAL)
		if [ -z "${LOCAL_TARGET}" ]; then
			echo "The LOCAL_TARGET environment variable have not been defined."
			exit
		fi
		ERROR_MESSAGE="The LOCAL_TARGET variable does not correspond to the RESTORE_TARGET variable."
		validate_bkp_target ${LOCAL_TARGET} "^/" "${ERROR_MESSAGE}"
		;;
	GOOGLE_DRIVE)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "CLOUD_TARGET" "${ERROR_MESSAGE}"
		;;
	AWS)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		;;
	*)
		echo "The value ${RESTORE_TARGET} in RESTORE_TARGET variable is not supported."
		exit
		;;
	esac
}

check_backup_target_config() {
	if [ -z "${CLOUD_TARGET}" ] && [ -z "${LOCAL_TARGET}" ]; then
		echo "No target defined."
		exit
	fi

	ERROR_MESSAGE="The value in CLOUD_TARGET variable is invalid."

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^gdocs")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
		cloud_bkps bash -c "[[ ! -f /credentials/googledrive.cred ]] && list"
	fi

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^s3")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
	fi

	if [ "${LOCAL_TARGET}" ]; then
		ERROR_MESSAGE="The value in LOCAL_TARGET variable is invalid."
		validate_bkp_target ${LOCAL_TARGET} "^/" "${ERROR_MESSAGE}"
	fi
}

multi_backup_config() {
	cat >"$1" <<EOF
[
]
EOF

	if [ "${LOCAL_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >>$1
	fi

	if [ "${CLOUD_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >>$1
	fi

}

restore_config() {
	cat >"$1" <<EOF
[
 { "description": "Local disk test", "url": "${CLOUD_TARGET}/$2" }
]
EOF
}

backup_container_operation()
{
	docker container "$1" "${BACKUP_CONTAINER_NAME}" > /dev/null
}

set_variables_environment "${ENV_OCARIOT}"

BACKEND_VAULT="consul"
BACKUP_CONTAINER_NAME="volumerize"

VALIDATING_OPTIONS=$(echo "$@" | sed 's/ /\n/g' |
	grep -P "(\-\-services|\-\-time|\-\-expression|\-\-keys).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo "$@" | grep -wo '\-\-services')
SERVICES=$(echo "$@" | grep -o -P '(?<=--services ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_TIME_PARAMETER=$(echo "$@" | grep -wo '\-\-time')
RESTORE_TIME=$(echo "$@" | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

CHECK_AUTO_BKP_PARAMETER=$(echo "$@" | grep -wo '\-\-expression')
EXPRESSION_BKP=$(echo "$@" | grep -o -P '(?<=--expression ).*' | sed 's/--.*//g')

CHECK_KEY_PARAMETER=$(echo "$@" | grep -wo '\-\-keys')
KEY_DIRECTORY=$(echo "$@" | grep -o -P '(?<=--keys ).*' | sed "s/--.*//g")

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) ||
	([ "$2" != "--services" ] && [ "$2" != "--time" ] && [ "$2" != "--keys" ] &&
		[ "$2" != "--expression" ] && [ "$2" != "--path" ] && [ "$2" != "" ]) ||
	[ ${VALIDATING_OPTIONS} ] ||
	([ ${CHECK_NAME_PARAMETER} ] && [ "${SERVICES}" = "" ]) ||
	([ ${CHECK_KEY_PARAMETER} ] && [ "$(validate_file_path ${KEY_DIRECTORY})" ]) ||
	([ ${CHECK_AUTO_BKP_PARAMETER} ] && [ "${EXPRESSION_BKP}" = "" ]) ||
	([ ${CHECK_TIME_PARAMETER} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
	stack_help
fi

if ([ $1 = "backup" ] && [ ${CHECK_TIME_PARAMETER} ]) ||
	([ $1 = "restore" ] && [ ${CHECK_AUTO_BKP_PARAMETER} ]); then
	stack_help
fi

check_backup_target_config

if [ ${RESTORE_TIME} ]; then
	RESTORE_TIME="--time ${RESTORE_TIME}"
fi

COMMAND="backupFull"
BACKUP_VOLUME_PROPERTY=""
SOURCE_VOLUME_PROPERTY=":ro"

if [ "$1" = "restore" ]; then
	if [ ${CHECK_KEY_PARAMETER} ]; then
		cp ${KEY_DIRECTORY} ${INSTALL_PATH}/config/ocariot/vault/.keys
		echo "Keys restored with success!"
	fi
	COMMAND="restore ${RESTORE_TIME}"
	BACKUP_VOLUME_PROPERTY=":ro"
	SOURCE_VOLUME_PROPERTY=""

	check_restore_target_config
fi

if [ ${CHECK_AUTO_BKP_PARAMETER} ]; then

	CRONTAB_COMMAND="${EXPRESSION_BKP} ${INSTALL_PATH}/ocariot stack backup ${SERVICES} >> /tmp/ocariot_backup.log"

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

# Verifying if backup folder exist
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
		SERVICES=$(cloud_bkps ${VOLUME_COMMAND} |
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
			CLOUD_BACKUPS=$(cloud_bkps ${VOLUME_COMMAND})
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
	INCREMENT=$((INCREMENT + 1))
done

PROCESS_BKP="OK"
BKP_CONFIG_MODEL=$(mktemp --suffix=.json)

docker run -d \
	--name ${BACKUP_CONTAINER_NAME} \
	${VOLUMES} \
	-v ${LOCAL_TARGET}:/local-backup${BACKUP_VOLUME_PROPERTY} \
	-v google_credentials:/credentials \
	-v ${BKP_CONFIG_MODEL}:/etc/volumerize/multiconfig.json:rw \
	blacklabelops/volumerize &> /dev/null

if [ -z "${RETENTION_DATA}" ]; then
	RETENTION_DATA="15D"
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

	docker exec -ti \
		-e VOLUMERIZE_SOURCE=/source/${VOLUME} \
		-e VOLUMERIZE_TARGET="multi:///etc/volumerize/multiconfig.json?mode=mirror&onfail=abort" \
		-e GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID} \
		-e GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY} \
		-e AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID} \
		-e AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY} \
		${BACKUP_CONTAINER_NAME} bash -c "${COMMAND} && remove-older-than ${RETENTION_DATA} --force"

	if [ $? != 0 ]; then
		PROCESS_BKP=FALSE
		echo "Error during $1 operation"
		break
	fi
	INCREMENT=$((INCREMENT + 1))
done

backup_container_operation stop && backup_container_operation rm

if [ "${PROCESS_BKP}" = "OK" ]; then
	RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g')

	if [ "${RUNNING_SERVICES}" ]; then
		${INSTALL_PATH}/scripts/stack/start.sh
	fi
fi
