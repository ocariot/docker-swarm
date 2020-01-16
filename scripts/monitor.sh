#!/usr/bin/env bash

INSTALL_PATH="/opt/docker-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

STACK_NAME="monitor"

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "\-\-stop.*" -v | grep '\-\-')

CHECK_STOP_OPTION=$(echo $@ | grep -wo '\-\-stop')
STOP_PARAMETER_VALUE=$(echo $@ | grep -o -P '(?<=--stop ).*' | sed 's/--.*//g')

if ([ "$1" != "--stop" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_STOP_OPTION} ] && [ "$(echo ${STOP_PARAMETER_VALUE} | wc -w)" != 0 ]); then
    help
fi

if [ "$(docker stack ls | grep ${STACK_NAME})" != "" ]; then
    if [ ${CHECK_STOP_OPTION} ]; then
        docker stack rm ${STACK_NAME}
        exit
    fi
    echo "Container health monitoring is already active."
else
    if [ ! ${CHECK_STOP_OPTION} ]; then
        docker stack deploy -c ${INSTALL_PATH}/docker-monitor-stack.yml ${STACK_NAME}
        exit
    fi
    echo "Container health monitoring is already stop."
fi
