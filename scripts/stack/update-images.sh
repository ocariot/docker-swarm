#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

VERSION="latest"
BACKEND_VAULT="consul"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-services).*" -v | grep '\-\-')

CHECK_SERVICE_PARAMETER=$(echo $@ | grep -wo '\-\-services')
SERVICES=$(echo $@ | grep -o -P '(?<=--services ).*' | sed "s/--.*//g;s/vault/vault ${BACKEND_VAULT}/g")

if ([ "$1" != "--services" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_SERVICE_PARAMETER} ] && [ "${SERVICES}" = "" ]); then

    stack_help
fi
set_variables_environment

if [ "${SERVICES}" = "" ];
then
    RUNNING_SERVICES=$(docker stack ps ${OCARIOT_STACK_NAME} --format {{.Name}} | sed 's/\..*//g')
    IMAGES="${IMAGES_NAME} $(docker image ls \
        --format {{.Repository}} \
        | sort -u \
        | grep ocariot/)"
fi

for CONTAINER_NAME in ${SERVICES};
do
    SERVICE_NAME=$(docker service ls \
        --filter name=${OCARIOT_STACK_NAME} \
        --format "{{.Name}}" \
        | grep -w ${OCARIOT_STACK_NAME}_.*${CONTAINER_NAME})

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
  ${INSTALL_PATH}/scripts/stack/start.sh
fi
