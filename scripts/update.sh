#!/usr/bin/env bash

INSTALL_PATH="/opt/docker-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

VERSION="latest"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-service).*" -v | grep '\-\-')

CHECK_SERVICE_PARAMETER=$(echo $@ | grep -wo '\-\-service')
SERVICES=$(echo $@ | grep -o -P '(?<=--service ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

if ([ "$1" != "--service" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_SERVICE_PARAMETER} ] && [ "${SERVICES}" = "" ]); then

    help
fi
set_variables_environment

if [ "${SERVICES}" = "" ];
then
    RUNNING_SERVICES=$(docker stack ps ocariot --format {{.Name}} | sed 's/\..*//g')
    IMAGES="${IMAGES_NAME} $(docker image ls \
        --format {{.Repository}} \
        | sort -u \
        | grep ocariot/)"
fi

for CONTAINER_NAME in ${SERVICES};
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

RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g' )

if [ "${RUNNING_SERVICES}" ]; then
  ${INSTALL_PATH}/scripts/start.sh
fi
