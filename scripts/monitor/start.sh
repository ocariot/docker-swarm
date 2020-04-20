#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

if [ "$#" -ne 0 ]; then
    monitor_help
    exit
fi

if [ -z "$(docker stack ls --format {{.Name}} | grep -w ${OCARIOT_STACK_NAME})" ];
then
  echo "It is necessary to initialize the ocariot services stack" \
    "(sudo ocariot stack start) to make the Monitor accessible in the browser."
fi

if [ -z "$(docker stack ls --format {{.Name}} | grep -w ${MONITOR_STACK_NAME})" ];
then
	docker stack rm ${MONITOR_STACK_NAME} &> /dev/null
fi

create_network

set_variables_environment "${ENV_MONITOR}"

docker stack deploy -c ${INSTALL_PATH}/docker-monitor-stack.yml ${MONITOR_STACK_NAME} --resolve-image changed
