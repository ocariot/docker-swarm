#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

source ${INSTALL_PATH}/scripts/functions.sh

PROCESSES_NUMBER=$(ps aux \
    | grep -w service_monitor.sh \
    | sed '/grep/d' \
    | wc -l)

if [ "${PROCESSES_NUMBER}" -gt 2 ]; then
    echo "Sevice monitor already initialized"
    exit
fi

docker events \
    --filter type=container \
    --filter 'event=destroy' \
    --filter 'event=create' \
    --format '{{json .Actor.Attributes.name}} {{json .Action}}' \
    | while read event; do
        docker stack ps ocariot &> /dev/null
        if [ $? = 0  ];
        then
            EVENT=$(echo ${event} \
                    | sed 's/"//g')
            CONTAINER_NAME=$(echo ${EVENT} | awk '{print $1}' | grep ocariot)
            ACTION=$(echo ${EVENT} | awk '{print $2}')

            SCRIPT_NAME="create_tokens"
            if [ "${ACTION}" = "destroy" ];
            then
                SCRIPT_NAME="remove_tokens"
            fi

            if [ ${CONTAINER_NAME} ];then
                execute_script ${CONTAINER_NAME} ${SCRIPT_NAME}
            fi
        fi
    done
