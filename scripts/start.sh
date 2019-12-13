#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

source ${INSTALL_PATH}/scripts/functions.sh

STACK_NAME="ocariot"

if [ "$#" -ne 0 ]; then
    help
    exit
fi

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

    CERTS_CONSUL=$(ls ${INSTALL_PATH}/config/consul/.certs/)
    CERTS_VAULT=$(ls ${INSTALL_PATH}/config/vault/.certs/)

    if [ "${CERTS_CONSUL}" = "" ] || [ "${CERTS_VAULT}" = "" ];
    then
        # Creating server certificates for consul and client
        # certificates for VAULT access to CONSUL through SSL/TLS
        ${INSTALL_PATH}/config/consul/create-consul-and-vault-certs.sh > /dev/null 2>&1
    fi
fi

${INSTALL_PATH}/scripts/service_monitor.sh >> /tmp/ocariot_monitor_service.log &

# Executing the services in mode swarm defined in docker-compose.yml file
docker stack deploy -c ${INSTALL_PATH}/docker-compose.yml ${STACK_NAME}

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then
    # Waiting Startup Vault
    waiting_vault ${STACK_NAME}

    # Monitoring Vault service
    docker service logs ${STACK_NAME}_vault -f 2> /dev/null
fi
