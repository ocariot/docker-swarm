#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

if [ "$#" -ne 0 ]; then
    monitor_help
    exit
fi

if [ "$(docker stack ls | grep ${MONITOR_STACK_NAME})" != "" ]; then
    docker stack rm ${MONITOR_STACK_NAME}
else
    echo "Container health monitoring is already stop."
fi
