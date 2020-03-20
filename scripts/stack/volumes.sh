#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

check_crontab()
{
    RET_CRONTAB_COMMAND=$(crontab -u ${USER} -l | grep -F "$1")

    if [ "${RET_CRONTAB_COMMAND}" ]; then
        echo "enable"
    else
        echo "disable"
    fi
}

remove_volumes()
{
    for VOLUME_NAME in $1; do

        VOLUME=$(docker volume ls --filter "name=${VOLUME_NAME}" --format {{.Name}})

        if [ ! ${VOLUME} ];
        then
            continue
        fi

        RET=1
        printf "Removing Volume: ${VOLUME_NAME}"
        while [[ ${RET} -ne 0 ]]
        do
            printf "."
            docker volume rm ${VOLUME_NAME} -f &> /dev/null
            RET=$?
        done
        printf "\n"
    done
}

validate_file_path()
{
  ls $1 &> /dev/null
  if [ $? != 0 ]; then
    echo "Path $1 not found!"
  fi
}

registre_bkp_vault()
{
    STACK_ID=$(docker stack ps ${OCARIOT_STACK_NAME} --format "{{.ID}}" --filter "name=${OCARIOT_STACK_NAME}_vault" --filter "desired-state=running")
    CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
    echo "Executando script $2 para: $1"
    docker exec -t ${CONTAINER_ID} vault kv put secret/map-accessor-token bkp_realized=true
}


BACKEND_VAULT="consul"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' \
  | grep -P "(\-\-services|\-\-time|\-\-expression|\-\-path|\-\-keys).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-services')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--services ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_BKP_DIRECTORY_PARAMETER=$(echo $@ | grep -wo '\-\-path')
BKP_DIRECTORY=$(echo $@ | grep -o -P '(?<=--path ).*' | sed "s/--.*//g")

CHECK_TIME_PARAMETER=$(echo $@ | grep -wo '\-\-time')
RESTORE_TIME=$(echo $@ | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

CHECK_AUTO_BKP_PARAMETER=$(echo $@ | grep -wo '\-\-expression')
EXPRESSION_BKP=$(echo "$@" | grep -o -P '(?<=--expression ).*' | sed 's/--.*//g')

CHECK_KEY_PARAMETER=$(echo $@ | grep -wo '\-\-keys')
KEY_DIRECTORY=$(echo $@ | grep -o -P '(?<=--keys ).*' | sed "s/--.*//g")

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) \
    || ([ "$2" != "--services" ] && [ "$2" != "--time" ] && [ "$2" != "--keys" ] && \
       [ "$2" != "--expression" ] && [ "$2" != "--path" ] && [ "$2" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]) \
    || ([ ${CHECK_BKP_DIRECTORY_PARAMETER} ] && [ "$(validate_file_path ${BKP_DIRECTORY})" != "" ]) \
    || ([ ${CHECK_KEY_PARAMETER} ] && [ "$(validate_file_path ${KEY_DIRECTORY})" != "" ]) \
    || ([ ${CHECK_AUTO_BKP_PARAMETER} ] && [ "${EXPRESSION_BKP}" = "" ]) \
    || ([ ${CHECK_TIME_PARAMETER} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
    stack_help
fi

if [ ! ${CHECK_BKP_DIRECTORY_PARAMETER} ]; then
    BKP_DIRECTORY="$(pwd)"
fi

if [ ${RESTORE_TIME} ]; then
    RESTORE_TIME="--time ${RESTORE_TIME}"
fi

COMMAND="backup"
BACKUP_VOLUME_PROPERTY=""
SOURCE_VOLUME_PROPERTY=":ro"

if [ "$1" = "restore" ]; then
    if [ ${CHECK_KEY_PARAMETER} ];
    then
        cp ${KEY_DIRECTORY} ${INSTALL_PATH}/config/ocariot/vault/.keys
        echo "Keys restored with success!"
    fi
    COMMAND="restore ${RESTORE_TIME}"
    BACKUP_VOLUME_PROPERTY=":ro"
    SOURCE_VOLUME_PROPERTY=""
fi

if ([ ${COMMAND} = "backup" ] && [ ${CHECK_TIME_PARAMETER} ]) \
    || ([ ${COMMAND} = "restore" ] && [ ${CHECK_AUTO_BKP_PARAMETER} ]);then
    stack_help
fi

if [ ${CHECK_AUTO_BKP_PARAMETER} ];then

    CRONTAB_COMMAND="${EXPRESSION_BKP} ${INSTALL_PATH}/ocariot stack ${COMMAND} ${CONTAINERS_BKP} --path ${BKP_DIRECTORY} >> /tmp/ocariot_backup.log"

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
        crontab -u ${USER} -l
        echo "Backup is already scheduled"
        exit
    fi
    ( crontab -u ${USER} -l; echo "${CRONTAB_COMMAND}" ) | crontab -u ${USER} -

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
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
EXPRESSION_GREP=$(echo "${OCARIOT_VOLUMES}" | sed 's/ /|/g')

# Verifying if backup folder exist
if [ "$1" = "restore" ];
then
    DIRECTORIES=$(ls ${BKP_DIRECTORY} 2> /dev/null)
    if [ $? -ne 0 ];then
        echo "Directory not found."
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

if [ "${CONTAINERS_BKP}" = "" ]; then
	if [ "$1" = "backup" ];
  then
      CONTAINERS_BKP=$(docker volume ls --format "{{.Name}}" \
          | grep -oE "${EXPRESSION_GREP}" \
          | sed 's/\(psmdb-\|psmysql-\|ocariot-\|-data\|redis-\)//g')
  else
      CONTAINERS_BKP=$(ls ${BKP_DIRECTORY} \
          | grep -oE "${EXPRESSION_GREP}" \
          | sed 's/\(psmdb-\|psmysql-\|ocariot-\|-data\|redis-\)//g')
  fi
fi

CONTAINERS_BKP=$(echo ${CONTAINERS_BKP} | tr " " "\n" | sed "s/vault/${BACKEND_VAULT}/g" | sort -u)

for CONTAINER_NAME in ${CONTAINERS_BKP};
do
    SERVICE_NAME=$(docker stack services ${OCARIOT_STACK_NAME} --format={{.Name}} \
        | grep -w ${OCARIOT_STACK_NAME}_.*${CONTAINER_NAME})
    RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"

    if [ "$1" = "backup" ];
    then
        MESSAGE="Volume BKP ${CONTAINER_NAME} not found!"
        VOLUME_NAME=$(docker volume ls \
            --format "{{.Name}}" \
            | grep -oE "${EXPRESSION_GREP}" \
            | grep -w ${CONTAINER_NAME} )
    else
        MESSAGE="Not found ${CONTAINER_NAME} volume!"
        VOLUME_NAME=$(ls ${BKP_DIRECTORY} \
            | grep -oE "${EXPRESSION_GREP}" \
            | grep -w ${CONTAINER_NAME})
    fi

    if [ -z "${VOLUME_NAME}" ]
    then
        echo "${MESSAGE}"
        exit
    fi
    VOLUMES_BKP="${VOLUMES_BKP} ${VOLUME_NAME}"
done

if [ -z "${VOLUMES_BKP}" ];
then
    echo "Not found ${OCARIOT_STACK_NAME} volumes!"
    exit
fi

if [ ! $(find /tmp -maxdepth 1 -name cache-ocariot) ]
then
    mkdir /tmp/cache-ocariot
fi

INCREMENT=1
for VOLUME in ${VOLUMES_BKP};
do
    VOLUMES="${VOLUMES} -v ${VOLUME}:/source/${VOLUME}${SOURCE_VOLUME_PROPERTY}"
    VOLUMES_CACHE="${VOLUMES_CACHE} -v /tmp/cache-ocariot/${VOLUME}:/volumerize-cache/${VOLUME}"
    ENVIRONMENTS_SOURCE="${ENVIRONMENTS_SOURCE} -e VOLUMERIZE_SOURCE${INCREMENT}=/source/${VOLUME}"
    ENVIRONMENTS_TARGET="${ENVIRONMENTS_TARGET} -e VOLUMERIZE_TARGET${INCREMENT}=file:///backup/${VOLUME}"
    ENVIRONMENTS_CACHE="${ENVIRONMENTS_CACHE} -e VOLUMERIZE_CACHE${INCREMENT}=/volumerize-cache/${VOLUME}"
    INCREMENT=$((INCREMENT + 1))
done

if [  "$(echo ${RUNNING_SERVICES} | grep ${BACKEND_VAULT})" ];
then
    RUNNING_SERVICES="${RUNNING_SERVICES} ${OCARIOT_STACK_NAME}_vault"
    registre_bkp_vault
fi

remove_services "${RUNNING_SERVICES}"

if [ "$1" = "restore" ];
then
    remove_volumes "${VOLUMES_BKP}"
fi

docker run --rm \
    --name volumerize \
    ${VOLUMES} \
    ${VOLUMES_CACHE} \
    -v ${BKP_DIRECTORY}:/backup${BACKUP_VOLUME_PROPERTY} \
    ${ENVIRONMENTS_SOURCE} \
    ${ENVIRONMENTS_TARGET} \
    blacklabelops/volumerize /bin/bash -c "${COMMAND}" \
    && PROCESS_BKP="OK"

if [ "${PROCESS_BKP}" = "OK" ]; then
  RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g' )

  if [ "${RUNNING_SERVICES}" ]; then
    ${INSTALL_PATH}/scripts/stack/start.sh
  fi
fi

rm -rf  /tmp/cache-ocariot