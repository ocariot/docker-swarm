#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

source ${INSTALL_PATH}/scripts/functions.sh

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-name|\-\-time).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-name')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--name ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_TIME_PARAMETER=$(echo $@ | grep -wo '\-\-time')
RESTORE_TIME=$(echo $@ | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) \
    || ([ "$2" != "--name" ] && [ "$2" != "--time" ] && [ "$2" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]) \
    || ([ ${CHECK_TIME_PARAMETER} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
    help
fi

if [ ${RESTORE_TIME} ]; then
    RESTORE_TIME="--time ${RESTORE_TIME}"
fi

BACKEND_VAULT="consul"

COMMAND="backup"
BACKUP_VOLUME_PROPERTY=""
SOURCE_VOLUME_PROPERTY=":ro"

if [ "$1" = "restore" ]; then
    COMMAND="restore ${RESTORE_TIME}"
    BACKUP_VOLUME_PROPERTY=":ro"
    SOURCE_VOLUME_PROPERTY=""
fi

VOLUMES_BKP=""
RUNNING_SERVICES=""

# Verifying if backup folder exist
if [  "$1" = "restore" ] && [ "$(ls ${INSTALL_PATH}/backups 2> /dev/null | wc -l)" = 0 ];
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
        CONTAINERS_BKP=$(ls ${INSTALL_PATH}/backups/ \
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
        VOLUME_NAME=$(ls ${INSTALL_PATH}/backups/ \
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

# Verifying if backup folder exist
if [ ! $(find ${INSTALL_PATH} -maxdepth 1 -name backups) ]
then
    mkdir backups
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
    -v ${INSTALL_PATH}/backups:/backup${BACKUP_VOLUME_PROPERTY} \
    ${ENVIRONMENTS_SOURCE} \
    ${ENVIRONMENTS_TARGET} \
    blacklabelops/volumerize /bin/bash -c "${COMMAND}" \
    && ${INSTALL_PATH}/scripts/start.sh

rm -rf  /tmp/cache-ocariot
