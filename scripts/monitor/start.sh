#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

STACK_NAME="monitor"

if [ "$#" -ne 0 ]; then
    monitor_help
    exit
fi

if [ "$(docker stack ls | grep ${STACK_NAME})" = "" ]; then
    docker stack deploy -c ${INSTALL_PATH}/docker-monitor-stack.yml ${STACK_NAME}
else
    echo "Container health monitoring is already active."
fi
