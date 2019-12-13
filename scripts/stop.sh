#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

source ${INSTALL_PATH}/scripts/functions.sh

STACK_NAME="ocariot"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-name|\-\-clear\-volumes).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-name')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--name ).*' | sed "s/--.*//g;s/vault/${BACKEND_VAULT}/g")

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/--.*//g')

if ([ "$1" != "--name" ] && [ "$1" != "--clear-volumes" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]) \
    || ([ ${CHECK_CLEAR_VOLUMES_PARAMETER} ] && [ "$(echo ${CLEAR_VOLUMES_VALUE} | wc -w)" != 0 ]); then

    help
fi

for CONTAINER_NAME in ${CONTAINERS_BKP};
do
    SERVICE_NAME=$(docker service ls \
        --filter name=ocariot \
        --format "{{.Name}}" \
        | grep -w ocariot_.*${CONTAINER_NAME})

    if [ ! "${SERVICE_NAME}" ]; then
        echo "Service ${CONTAINER_NAME} not found!"
        exit
    fi
    RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"
done

REMOVE_STACK=false
if [ "${CONTAINERS_BKP}" = "" ];
then
    RUNNING_SERVICES=$(docker stack ps ocariot --format {{.Name}} | sed 's/\..*//g')
    REMOVE_STACK=true
fi

if ${REMOVE_STACK}; then
    remove_stack
    clear_environment
else
    remove_services "${RUNNING_SERVICES}"
fi

# If "-clear-volumes" parameter was passed the
# volumes will be excluded
if [ ${CHECK_CLEAR_VOLUMES_PARAMETER} ];then
    clear_volumes "${CONTAINERS_BKP}" &> /dev/null
fi
