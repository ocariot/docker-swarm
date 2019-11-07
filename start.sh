#!/usr/bin/env bash

# Cleaning all files that contain the access tokens
clear_tokens()
{
    # Directory where access tokens are placed
    TOKEN_DIR=$(pwd)/config/vault/tokens/
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
        docker build --tag ocariot-rabbitmq config/rabbitmq
    fi
}

# General function for setting up the environment
# before starting services
configure_environment()
{
    # Verifying the existence of .env file
    if [ ! $(find ./ -name .env) ]
    then
        echo "\".env\" file not found!!!"

        # Finishing the script execution
        exit
    fi

    # Executing .env to capture environment variable defined in it
    set -a && . .env && set +a

    mkdir config/vault/tokens 2> /dev/null

    # creating the files that will be used to share
    # the vault access token
    FILES_TOKEN=$(ls config/vault/policies/ | sed "s/.hcl//g")
    for FILE_TOKEN in ${FILES_TOKEN}; do
        touch config/vault/tokens/access-token-${FILE_TOKEN}
        if [ $? -ne 0 ]
        then
            exit
        fi
    done

    # creating the file where the root token will be
    # stored, along with the encryption keys
    touch config/vault/keys
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

# Waiting Startup Vault
waiting_vault()
{
   docker stack ps $1 > /dev/null 2>&1
   if [ "$?" -ne 1 ]; then
       COMMAND="docker stack ps ocariot -f name=ocariot_vault 2> /dev/null | grep Running"
       VAULT_RET=$(bash -c "${COMMAND}")
       printf "Waiting Startup Vault"
       while [[ ${VAULT_RET} == "" ]]
       do
          VAULT_RET=$(bash -c "${COMMAND}")
          printf "."
          sleep 1
       done
       printf "\n"
  fi
}

if [ "$#" -ne 1 ]; then
    echo -e "Illegal number of parameters. \nExample Usage: \n\t sudo ./start <STACK_NAME>"
    exit
fi

docker stack ps $1 > /dev/null 2>&1

if [ "$?" -ne 1 ]; then
    echo "$1 stack services already initialized"
    exit
fi

# General function for setting up the environment
# before starting services
configure_environment

# Verifying the existence of RabbitMQ image
verify_rabbitmq_image > /dev/null 2>&1

# Cleaning all files that contain the access tokens
clear_tokens > /dev/null 2>&1

# Creating server certificates for consul and client
# certificates for VAULT access to CONSUL through SSL/TLS
config/consul/create-consul-and-vault-certs.sh > /dev/null 2>&1

# Executing the services in mode swarm defined in docker-compose.yml file
docker stack deploy -c docker-compose.yml $1

# Waiting Startup Vault
waiting_vault $1

# Monitoring Vault service
docker service logs $1_vault -f
