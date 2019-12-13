#!/usr/bin/env bash

################# SERVICE MONITOR SCRIPT #################

check_vault()
{
    RESULT=$(docker service logs ocariot_vault 2> /dev/null | grep -c "Token Generation Enabled")
    echo ${RESULT}
}

execute_script()
{

    RET=$(check_vault)
    while [[ ${RET} != 1 ]];
    do
        if [ "$(docker stack ls | grep -w ocariot)" = "" ];
        then
            return
        fi
        RET=$(check_vault)
        sleep 3
    done

    STACK_ID=$(docker stack ps ocariot --format "{{.ID}}" --filter "name=ocariot_vault" --filter "desired-state=running")

    CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
    echo "Executando script $2 para: $1"
    docker exec -t ${CONTAINER_ID} /etc/vault/scripts/$2.sh $1
}

################# START SCRIPT #################

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
        docker build --tag ocariot-rabbitmq config/rabbitmq > /dev/null &
        waiting_rabbitmq
    fi
}

set_variables_environment()
{
    # Verifying the existence of .env file
    if [ ! $(find ${INSTALL_PATH} -name .env) ]
    then
        echo "\".env\" file not found!!!"

        # Finishing the script execution
        exit
    fi

    # Executing .env to capture environment variable defined in it
    set -a && . ${INSTALL_PATH}/.env && set +a
}
# General function for setting up the environment
# before starting services
configure_environment()
{
    set_variables_environment

    mkdir config/vault/tokens 2> /dev/null

    # creating the files that will be used to share
    # the vault access token
    FILES_TOKEN=$(ls ${INSTALL_PATH}/config/vault/policies/ | sed "s/.hcl//g")
    for FILE_TOKEN in ${FILES_TOKEN}; do
        touch ${INSTALL_PATH}/config/vault/tokens/access-token-${FILE_TOKEN}
        if [ $? -ne 0 ]
        then
            exit
        fi
    done

    # creating the file where the root token will be
    # stored, along with the encryption keys
    touch ${INSTALL_PATH}/config/vault/keys
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

################# STOP SCRIPT #################

clear_volumes()
{
    if [ $1 ]; then
        VOLUMES=$(docker volume ls \
            --format {{.Name}} \
            --filter "name=-$(echo $1 | sed 's/ /|-/g')")
    else
        VOLUMES=$(docker volume ls --format {{.Name}} |
            grep -P '(?<=ocariot-).*(?=-data)')
    fi

    for VOLUME in ${VOLUMES}
    do
        docker volume rm -f ${VOLUME}
    done
}

display_stop_service()
{
    # Verifying if the services was removed
    echo "Stoping service: $1"
    RET=1
    while [[ $RET -ne 0 ]]; do
        RET=$(docker service ls --filter "name=$1" | tail -n +2 | wc -l)
    done
}

remove_services()
{
    for SERVICE in $1
    do
        docker service rm ${SERVICE} &> /dev/null &
        display_stop_service ${SERVICE}
    done
}

remove_stack()
{
    # Stopping the ocariot stack services  that being run
    docker stack rm ${STACK_NAME} > /dev/null 2>&1

    # Verifying if the services was removed
    printf "Stoping services"
    RET=0
    while [[ $RET -eq 0 ]]; do
        docker stack ps ${STACK_NAME} > /dev/null 2>&1
        RET=$?
        sleep 3
        printf "."
    done
    printf "\n"
}

clear_environment()
{
    ps aux \
        | grep -w service_monitor.sh \
        | sed '/grep/d' \
        | awk '{system("kill -9 "$2)}'

    rm ${INSTALL_PATH}/config/vault/.certs/* -f
    rm ${INSTALL_PATH}/config/consul/.certs/* -f
}

################# VOLUMES SCRIPT #################

help()
{
    echo -e "Illegal number of parameters. \nExample Usage: \n\t ocariot \e[1m<action> <option>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t start: operation to be realize.\
                         \n \t\t stop: Command utilized to stop services. Options as \e[4m--name and --clear-volumes\e[0m can be used.\
                         \n \t\t update: operation to be realize.\
                         \n \t\t backup: operation to be realize.\
                         \n \t\t restore: operation to be realize.\
             \n\t\e[1m<option>\e[0m: \n \t\t --name <[list of container name]>: specific volume used by the services.\
                         \n \t\t --clear-volumes <[list of volume name]>: specific volume used by the services.\
                         \n \t\t --time <[list of volume name]>: specific volume used by the services."
    exit 1
}

restart_stack()
{
    mkdir ${INSTALL_PATH}/config/vault/tokens 2> /dev/null

    # creating the files that will be used to share
    # the vault access token
    FILES_TOKEN=$(ls ${INSTALL_PATH}/config/vault/policies/ | sed "s/.hcl//g")
    for FILE_TOKEN in ${FILES_TOKEN}; do
        touch ${INSTALL_PATH}/config/vault/tokens/access-token-${FILE_TOKEN}
        if [ $? -ne 0 ]
        then
            exit
        fi
    done

    docker stack deploy -c docker-compose.yml $1
}

stop_service()
{
    # Verifying if the services was removed
    echo "Stoping service: $1"
    RET=1
    while [[ $RET -ne 0 ]]; do
        RET=$(docker service ls --filter "name=$1" | tail -n +2 | wc -l)
    done
}

remove_volumes()
{
    for VOLUME_NAME in $1; do

        VOLUME=$(docker volume ls --filter "name=${VOLUME_NAME}" --format {{.Name}})

        if [ ! ${VOLUME} ];
        then
            continue
        fi

        RET=1
        printf "Removing Volume: ${VOLUME_NAME}"
        while [[ ${RET} -ne 0 ]]
        do
            printf "."
            docker volume rm ${VOLUME_NAME} -f &> /dev/null
            RET=$?
        done
        printf "\n"
    done
}
