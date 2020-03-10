#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

if [ "$#" -ne 0 ]; then
    monitor_help
    exit
fi

if [ "$(docker stack ls | grep -w ${OCARIOT_STACK_NAME})" = "" ];
then
  echo "It is necessary to initialize the ocariot services stack (sudo ocariot stack start) before starting the monitoring service."
  exit
fi

PARENT_PROCESS=$(ps -o args -p $PPID | tail -n +2 | grep -wo $(which ocariot))

if [ "$(docker stack ls | grep ${MONITOR_STACK_NAME})" ] && [ "${PARENT_PROCESS}" ]; then
  echo "Ocariot ocariot-monitor was already active."
  exit
fi

set_variables_environment "${ENV_MONITOR}"

docker stack deploy -c ${INSTALL_PATH}/docker-monitor-stack.yml ${MONITOR_STACK_NAME} --resolve-image changed
