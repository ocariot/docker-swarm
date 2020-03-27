#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

clear_volumes()
{
    if [ $1 ]; then
        VOLUMES=$(docker volume ls \
            --format {{.Name}} \
            --filter "name=-$(echo $1 | sed 's/ /|-/g')")
    else
        VOLUMES=$(docker volume ls --format {{.Name}} |
            grep -P '(?<=ocariot-).*(?=-data)' |
            grep -v "$(echo ${MONITOR_STACK_NAME} | sed 's/_/-/g')")
    fi

    for VOLUME in ${VOLUMES}
    do
        RET=1
        printf "Removing Volume: ${VOLUME}"
        while [[ ${RET} -ne 0 ]]
        do
            printf "."
            docker volume rm ${VOLUME} -f &> /dev/null
            RET=$?
        done
        printf "\n"
    done
}

remove_stack_config()
{
    # Stopping the ocariot stack services  that being run
    docker stack rm ${OCARIOT_STACK_NAME} > /dev/null 2>&1

    # Verifying if the services was removed
    printf "Removing stack configurations"
    while [[ $(docker stack ps ${OCARIOT_STACK_NAME} &> /dev/null; echo $?) -eq 0 ]]; do
        sleep 2
        printf "."
    done
    printf "\n"
}

clear_environment()
{
    rm ${INSTALL_PATH}/config/ocariot/vault/.certs/* -f
    rm ${INSTALL_PATH}/config/ocariot/consul/.certs/* -f
}

BACKEND_VAULT="consul"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-services|\-\-clear\-volumes).*" -v | grep '\-\-')

CHECK_SERVICE_PARAMETER=$(echo $@ | grep -wo '\-\-services')
SERVICES=$(echo $@ | grep -o -P '(?<=--services ).*' | sed "s/--.*//g;s/vault/vault ${BACKEND_VAULT}/g")

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/--.*//g')

if ([ "$1" != "--services" ] && [ "$1" != "--clear-volumes" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_SERVICE_PARAMETER} ] && [ "${SERVICES}" = "" ]) \
    || ([ ${CHECK_CLEAR_VOLUMES_PARAMETER} ] && [ "$(echo ${CLEAR_VOLUMES_VALUE} | wc -w)" != 0 ]); then

    stack_help
fi

if [ ! "$(docker stack ls | grep ${OCARIOT_STACK_NAME})" ]; then
  echo "The ${OCARIOT_STACK_NAME} stack is not active."
  # If "--clear-volumes" parameter was passed the
  # volumes will be excluded
  if [ ${CHECK_CLEAR_VOLUMES_PARAMETER} ];then
      clear_volumes "${SERVICES}"
      sudo rm -rf ${INSTALL_PATH}/config/ocariot/vault/.keys
  fi
  exit
fi

for CONTAINER_NAME in ${SERVICES};
do
    SERVICE_NAME=$(docker service ls \
        --filter name=${OCARIOT_STACK_NAME} \
        --format "{{.Name}}" \
        | grep -w ${OCARIOT_STACK_NAME}_.*${CONTAINER_NAME})

    if [ ! "${SERVICE_NAME}" ]; then
        echo "Service ${CONTAINER_NAME} not found!"
        exit
    fi
    RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"
done

REMOVE_STACK_CONFIG=false
if [ "${SERVICES}" = "" ];
then
    RUNNING_SERVICES=$(docker stack ps ${OCARIOT_STACK_NAME} --format {{.Name}} | sed 's/\..*//g')
    REMOVE_STACK_CONFIG=true
fi

remove_services "${RUNNING_SERVICES}"

if ${REMOVE_STACK_CONFIG}; then
    remove_stack_config
    clear_environment
fi

# If "--clear-volumes" parameter was passed the
# volumes will be excluded
if [ ${CHECK_CLEAR_VOLUMES_PARAMETER} ];then
    clear_volumes "${SERVICES}"
    sudo rm -rf ${INSTALL_PATH}/config/ocariot/vault/.keys
fi

delete_network
