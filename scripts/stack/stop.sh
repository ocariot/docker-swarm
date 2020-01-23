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
            grep -P '(?<=ocariot-).*(?=-data)')
    fi

    for VOLUME in ${VOLUMES}
    do
        docker volume rm -f ${VOLUME}
    done
}

remove_stack()
{
    # Stopping the ocariot stack services  that being run
    docker stack rm ${STACK_NAME} > /dev/null 2>&1

    # Verifying if the services was removed
    printf "Stoping services"
    RET=0
    while [[ $RET -eq 0 ]]; do
        docker stack ps ${STACK_NAME} > /dev/null 2>&1
        RET=$?
        sleep 3
        printf "."
    done
    printf "\n"
}

clear_environment()
{
    ps aux \
        | grep -w service_monitor.sh \
        | sed '/grep/d' \
        | awk '{system("kill -9 "$2)}'

    rm ${INSTALL_PATH}/config/ocariot/vault/.certs/* -f
    rm ${INSTALL_PATH}/config/ocariot/consul/.certs/* -f
}

STACK_NAME="ocariot"
BACKEND_VAULT="consul"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "(\-\-services|\-\-clear\-volumes).*" -v | grep '\-\-')

CHECK_SERVICE_PARAMETER=$(echo $@ | grep -wo '\-\-services')
SERVICES=$(echo $@ | grep -o -P '(?<=--services ).*' | sed "s/ --.*//g;s/vault/vault ${BACKEND_VAULT}/g")

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/ --.*//g')

if ([ "$1" != "--services" ] && [ "$1" != "--clear-volumes" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_SERVICE_PARAMETER} ] && [ "${SERVICES}" = "" ]) \
    || ([ ${CHECK_CLEAR_VOLUMES_PARAMETER} ] && [ "$(echo ${CLEAR_VOLUMES_VALUE} | wc -w)" != 0 ]); then

    stack_help
fi

docker stack ps ${STACK_NAME} > /dev/null 2>&1
STATUS_OCARIOT_STACK=$?

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then
  echo "The ocariot stack is not active."
  # If "-clear-volumes" parameter was passed the
  # volumes will be excluded
  if [ ${CHECK_CLEAR_VOLUMES_PARAMETER} ];then
      clear_volumes "${SERVICES}" &> /dev/null
      sudo rm -rf ${INSTALL_PATH}/config/ocariot/vault/.keys
  fi
  exit
fi

for CONTAINER_NAME in ${SERVICES};
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
if [ "${SERVICES}" = "" ];
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
    clear_volumes "${SERVICES}" &> /dev/null
    sudo rm -rf ${INSTALL_PATH}/config/ocariot/vault/.keys
fi

