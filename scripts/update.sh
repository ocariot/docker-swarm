#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

source ${INSTALL_PATH}/scripts/functions.sh

VERSION="latest"

STACK_NAME="ocariot"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-name).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-name')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--name ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/--.*//g')

if ([ "$1" != "--name" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]); then

    help
fi
set_variables_environment

if [ "${CONTAINERS_BKP}" = "" ];
then
    RUNNING_SERVICES=$(docker stack ps ocariot --format {{.Name}} | sed 's/\..*//g')
    IMAGES="${IMAGES_NAME} $(docker image ls \
        --format {{.Repository}} \
        | sort -u \
        | grep ocariot/)"
fi

for CONTAINER_NAME in ${CONTAINERS_BKP};
do
    SERVICE_NAME=$(docker service ls \
        --filter name=ocariot \
        --format "{{.Name}}" \
        | grep -w ocariot_.*${CONTAINER_NAME})

    if [ "${SERVICE_NAME}" ]; then
        RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"
    fi

    IMAGES_NAME="$(docker image ls \
        --format {{.Repository}} \
        | sort -u \
        | grep ocariot/${CONTAINER_NAME})"

    if [ ! ${IMAGES_NAME} ];then
        echo "Image of ${CONTAINER_NAME} container not found!"
        exit
    fi

    IMAGES="${IMAGES} ${IMAGES_NAME}"
done

remove_services "${RUNNING_SERVICES}"

for IMAGE in ${IMAGES}
do
    docker pull ${IMAGE}:${VERSION}
done

${INSTALL_PATH}/scripts/start.sh
