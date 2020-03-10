#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

# General function for setting up the environment
# before starting services
configure_environment()
{
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
    TOKEN_DIR=${INSTALL_PATH}/config/ocariot/vault/.tokens/
    # All access token files
    TOKEN_FILES=$(ls ${TOKEN_DIR})
    # Cleaning every access token files
    for TOKEN_FILE in ${TOKEN_FILES}; do
        > ${TOKEN_DIR}${TOKEN_FILE}
    done
}

# Waiting Startup Vault
waiting_vault()
{
   docker stack ps ${OCARIOT_STACK_NAME} > /dev/null 2>&1
   if [ "$?" -ne 1 ]; then
       COMMAND="docker stack ps ${OCARIOT_STACK_NAME}
          --filter name=${OCARIOT_STACK_NAME}_vault
          --format {{.CurrentState}}"
       printf "Waiting Startup Vault"
       while [[ "$(${COMMAND} 2> /dev/null | grep -w Running )" == "" ]]
       do
          printf "."
          sleep 1
       done
       printf "\n"
  fi
}

check_vault()
{
    RESULT=$(docker service logs ${OCARIOT_STACK_NAME}_vault 2> /dev/null | grep -c "Token Generation Enabled")
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

if [ "$#" -ne 0 ]; then
    stack_help
    exit
fi

GENERATE_KEYS_FILE="FALSE"

docker stack ps ${OCARIOT_STACK_NAME} > /dev/null 2>&1
STATUS_OCARIOT_STACK=$?

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then
    # General function for setting up the environment
    # before starting services
    configure_environment

    # Cleaning all files that contain the access tokens
    clear_tokens &> /dev/null

    CERTS_CONSUL=$(ls ${INSTALL_PATH}/config/ocariot/consul/.certs/ 2> /dev/null)
    CERTS_VAULT=$(ls ${INSTALL_PATH}/config/ocariot/vault/.certs/ 2> /dev/null)

    if [ "${CERTS_CONSUL}" = "" ] || [ "${CERTS_VAULT}" = "" ];
    then
        # Creating server certificates for consul and client
        # certificates for VAULT access to CONSUL through SSL/TLS
        ${INSTALL_PATH}/config/ocariot/consul/create-consul-and-vault-certs.sh &> /dev/null
    fi
fi

${INSTALL_PATH}/scripts/ocariot_watchdog.sh >> /tmp/ocariot_watchdog.log &

set_variables_environment "${ENV_OCARIOT}"

create_network

# Executing the services in mode swarm defined in docker-compose.yml file
docker stack deploy -c ${INSTALL_PATH}/docker-ocariot-stack.yml ${OCARIOT_STACK_NAME} --resolve-image changed

if [ "${STATUS_OCARIOT_STACK}" -ne 0 ]; then
    validate_keys "${GENERATE_KEYS_FILE}" &
    waiting_vault
    # Monitoring Vault service
    docker service logs ${OCARIOT_STACK_NAME}_vault -f 2> /dev/null
fi