#!/usr/bin/env bash

OCARIOT_STACK_NAME="ocariot"

check_vault()
{
    RESULT=$(docker service logs ${OCARIOT_STACK_NAME}_vault 2> /dev/null | grep -c "Token Generation Enabled")
    echo ${RESULT}
}

execute_script()
{

    RET=$(check_vault)
    while [[ ${RET} != 1 ]];
    do
        RET=$(check_vault)
    done

    STACK_ID=$(docker stack ps ${OCARIOT_STACK_NAME} --format "{{.ID}}" --filter "name=${OCARIOT_STACK_NAME}_vault" --filter "desired-state=running")

    CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
    echo "Executando script $2 para: $1"
    docker exec -t ${CONTAINER_ID} /etc/vault/scripts/$2.sh $1
}

PROCESSES_NUMBER=$(ps aux \
    | grep -w ocariot_watchdog.sh \
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
            EVENT=$(echo ${event} \
                    | sed 's/"//g')
        CONTAINER_NAME=$(echo ${EVENT} | awk '{print $1}' | grep ${OCARIOT_STACK_NAME})
        ACTION=$(echo ${EVENT} | awk '{print $2}')

        SCRIPT_NAME="create_tokens"
        if [ "${ACTION}" = "destroy" ];
        then
          SCRIPT_NAME="remove_tokens"
        fi

        if [ ${CONTAINER_NAME} ];then
          execute_script ${CONTAINER_NAME} ${SCRIPT_NAME}
        fi
    done
