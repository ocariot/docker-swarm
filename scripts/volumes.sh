#!/usr/bin/env bash

#INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"
INSTALL_PATH="/opt/docker-swarm"
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

stop_service()
{
    # Verifying if the services was removed
    echo "Stoping service: $1"
    RET=1
    while [[ $RET -ne 0 ]]; do
        RET=$(docker service ls --filter "name=$1" | tail -n +2 | wc -l)
    done
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

BACKEND_VAULT="consul"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' \
  | grep -P "(\-\-service|\-\-time|\-\-expression|\-\-location).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-service')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--service ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_BKP_DIRECTORY_PARAMETER=$(echo $@ | grep -wo '\-\-location')
BKP_DIRECTORY=$(echo $@ | grep -o -P '(?<=--location ).*' | sed "s/--.*//g")

CHECK_TIME_PARAMETER=$(echo $@ | grep -wo '\-\-time')
RESTORE_TIME=$(echo $@ | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

CHECK_AUTO_BKP_PARAMETER=$(echo $@ | grep -wo '\-\-expression')
EXPRESSION_BKP=$(echo "$@" | grep -o -P '(?<=--expression).*' | sed 's/--.*//g')

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) \
    || ([ "$2" != "--service" ] && [ "$2" != "--time" ] && \
       [ "$2" != "--expression" ] && [ "$2" != "--location" ] && [ "$2" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]) \
    || ([ ${CHECK_BKP_DIRECTORY_PARAMETER} ] && [ "$(validate_file_path ${BKP_DIRECTORY})" != "" ]) \
    || ([ ${CHECK_AUTO_BKP_PARAMETER} ] && [ "${EXPRESSION_BKP}" = "" ]) \
    || ([ ${CHECK_TIME_PARAMETER} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
    help
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
    COMMAND="restore ${RESTORE_TIME}"
    BACKUP_VOLUME_PROPERTY=":ro"
    SOURCE_VOLUME_PROPERTY=""
fi

if ([ ${COMMAND} = "backup" ] && [ ${CHECK_TIME_PARAMETER} ]) \
    || ([ ${COMMAND} = "restore" ] && [ ${CHECK_AUTO_BKP_PARAMETER} ]);then
    help
fi

if [ ${CHECK_AUTO_BKP_PARAMETER} ];then

    CRONTAB_COMMAND="${EXPRESSION_BKP} ${INSTALL_PATH}/ocariot ${COMMAND} ${CONTAINERS_BKP} -- location ${BKP_DIRECTORY} >> /tmp/ocariot_backup.log"

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
        echo "Backup is already scheduled"
        exit
    fi
    ( crontab -u ${USER} -l; echo "${CRONTAB_COMMAND}" ) | crontab -u ${USER} -

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
        echo "Backup schedule successful!"
    else
        echo "Unsuccessful backup schedule!"
    fi

    exit
fi

VOLUMES_BKP=""
RUNNING_SERVICES=""

# Verifying if backup folder exist
if [  "$1" = "restore" ] && [ "$(ls ${BKP_DIRECTORY} 2> /dev/null | wc -l)" = 0 ];
then
    echo "No container backup was found"
    exit
fi

if [ "${CONTAINERS_BKP}" = "" ]; then
	if [ "$1" = "backup" ];
    then
        CONTAINERS_BKP=$(docker volume ls --format "{{.Name}}" --filter name=ocariot \
            | sed 's/\(psmdb-\|ocariot-\|-data\|redis-\)//g')
    else
        CONTAINERS_BKP=$(ls ${BKP_DIRECTORY} \
            | grep -P 'ocariot.*data' \
            | sed 's/\(psmdb-\|ocariot-\|-data\|redis-\)//g')
    fi
fi

CONTAINERS_BKP=$(echo ${CONTAINERS_BKP} | sed "s/vault/${BACKEND_VAULT}/g")

for CONTAINER_NAME in ${CONTAINERS_BKP};
do
    SERVICE_NAME=$(docker service ls \
        --filter name=ocariot \
        --format "{{.Name}}" \
        | grep -w ocariot_.*${CONTAINER_NAME})
    RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"

    if [ "$1" = "backup" ];
    then
        MESSAGE="Volume BKP ${CONTAINER_NAME} not found!"
        VOLUME_NAME=$(docker volume ls \
            --filter name=ocariot \
            --format "{{.Name}}" \
            | grep -w ${CONTAINER_NAME})
    else
        MESSAGE="Not found ${CONTAINER_NAME} volume!"
        VOLUME_NAME=$(ls ${BKP_DIRECTORY} \
            | grep -w ${CONTAINER_NAME})
    fi

    if [ "${VOLUME_NAME}" = "" ]
    then
        echo "${MESSAGE}"
        exit
    fi
    VOLUMES_BKP="${VOLUMES_BKP} ${VOLUME_NAME}"
done

if [ "${VOLUMES_BKP}" = "" ];
then
    echo "Not found ocariot volumes!"
    exit
fi

if [ ! $(find /tmp -maxdepth 1 -name cache-ocariot) ]
then
    mkdir /tmp/cache-ocariot
fi

set_variables_environment

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
    RUNNING_SERVICES="${RUNNING_SERVICES} ocariot_vault"
fi

if [ "$#" = "1" ];
then
    RUNNING_SERVICES=$(docker stack ps ocariot --format {{.Name}} | sed 's/\..*//g')
fi

for SERVICE in ${RUNNING_SERVICES}
do
    docker service rm ${SERVICE} &> /dev/null &
    stop_service ${SERVICE}
done

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

RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g' )

if [ "${RUNNING_SERVICES}" ] && [ "${PROCESS_BKP}" = "OK" ]; then
  ${INSTALL_PATH}/scripts/start.sh
fi

rm -rf  /tmp/cache-ocariot
