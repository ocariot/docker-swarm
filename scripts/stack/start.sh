#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

# General function for setting up the environment
# before starting services
configure_environment()
{
    set_variables_environment

    mkdir ${INSTALL_PATH}/config/ocariot/vault/.tokens 2> /dev/null

    # creating the files that will be used to share
    # the vault access token
    FILES_TOKEN=$(ls ${INSTALL_PATH}/config/ocariot/vault/policies/ | sed "s/.hcl//g")
    for FILE_TOKEN in ${FILES_TOKEN}; do
        touch ${INSTALL_PATH}/config/ocariot/vault/.tokens/access-token-${FILE_TOKEN}
        if [ $? -ne 0 ]
        then
            exit
        fi
    done

    if [ ! $(ls ${INSTALL_PATH}/config/ocariot/vault/.keys 2> /dev/null)  ]; then
      touch ${INSTALL_PATH}/config/ocariot/vault/.keys
      GENERATE_KEYS_FILE="TRUE"
    fi
}

# Cleaning all files that contain the access tokens
clear_tokens()
{
    # Directory where access tokens are placed
    TOKEN_DIR=$(pwd)/config/ocariot/vault/tokens/
    # All access token files
    TOKEN_FILES=$(ls ${TOKEN_DIR})
    # Cleaning every access token files
    for TOKEN_FILE in ${TOKEN_FILES}; do
        > ${TOKEN_DIR}${TOKEN_FILE}
    done
}

# Verifying the existence of RabbitMQ image
verify_rabbitmq_image(){
    OCARIOT_RABBITMQ_IMAGE=$(docker image ls | grep ocariot-rabbitmq)

    if [[ ! ${OCARIOT_RABBITMQ_IMAGE} ]];then
        docker build --tag ocariot-rabbitmq config/ocariot/rabbitmq > /dev/null &
        waiting_rabbitmq
    fi
}

# Creating RabbitMQ image
waiting_rabbitmq()
{
    printf "Wait, We are creating RabbitMQ image for you ;)"
    COMMAND="docker image ls | grep ocariot-rabbitmq"
    RABBITMQ_RET=$(bash -c "${COMMAND}")
    while [[ ${RABBITMQ_RET} == "" ]]
    do
        RABBITMQ_RET=$(bash -c "${COMMAND}")
        printf "."
        sleep 1
    done
    printf "\n"
}

check_vault()
{
    RESULT=$(docker service logs ocariot_vault 2> /dev/null | grep -c "Token Generation Enabled")
    echo ${RESULT}
}

validate_keys()
{
    RET=$(check_vault)
    while [[ ${RET} != 1 ]];
    do
      RET=$(check_vault)
      sleep 3
    done

    if [ "$1" = "TRUE" ];then
      cp ${INSTALL_PATH}/config/ocariot/vault/.keys $(pwd)/keys &> /dev/null
    fi
}

STACK_NAME="ocariot"

if [ "$#" -ne 0 ]; then
    stack_help
    exit
fi

GENERATE_KEYS_FILE="FALSE"

docker stack ps ${STACK_NAME} > /dev/null 2>&1
STATUS_OCARIOT_STACK=$?

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then
    # General function for setting up the environment
    # before starting services

    configure_environment

    # Verifying the existence of RabbitMQ image
    verify_rabbitmq_image

    # Cleaning all files that contain the access tokens
    clear_tokens > /dev/null 2>&1

    CERTS_CONSUL=$(ls ${INSTALL_PATH}/config/ocariot/consul/.certs/ 2> /dev/null)
    CERTS_VAULT=$(ls ${INSTALL_PATH}/config/ocariot/vault/.certs/ 2> /dev/null)

    if [ "${CERTS_CONSUL}" = "" ] || [ "${CERTS_VAULT}" = "" ];
    then
        # Creating server certificates for consul and client
        # certificates for VAULT access to CONSUL through SSL/TLS
        ${INSTALL_PATH}/config/ocariot/consul/create-consul-and-vault-certs.sh &> /dev/null
    fi
else
    echo "Ocariot stack was already active."
fi

${INSTALL_PATH}/scripts/service_monitor.sh >> /tmp/ocariot_monitor_service.log &

# Executing the services in mode swarm defined in docker-compose.yml file
docker stack deploy -c ${INSTALL_PATH}/docker-ocariot-stack.yml ${STACK_NAME}

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then

    validate_keys "${GENERATE_KEYS_FILE}" &

    # Monitoring Vault service
    docker service logs ${STACK_NAME}_vault -f 2> /dev/null
fi