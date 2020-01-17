#!/usr/bin/env bash

#INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"
INSTALL_PATH="/opt/docker-swarm"

# Used for start, update and volumes scripts
set_variables_environment()
{
    # Verifying the existence of .env file
    if [ ! $(find ${INSTALL_PATH} -name .env) ]
    then
       if [ "$EUID" -ne 0 ]
          then echo "Please run as root"
          exit
       fi
       cp ${INSTALL_PATH}/.env.example ${INSTALL_PATH}/.env
       vi ${INSTALL_PATH}/.env
    fi

    # Executing .env to capture environment variable defined in it
    set -a && . ${INSTALL_PATH}/.env && set +a
}

# Used for start, update and volumes scripts
display_stop_service()
{
    # Verifying if the services was removed
    echo "Stoping service: $1"
    RET=1
    while [[ $RET -ne 0 ]]; do
        RET=$(docker service ls --filter "name=$1" | tail -n +2 | wc -l)
    done
}

# Used for stop and update scripts. Depend of display_stop_service function
remove_services()
{
    for SERVICE in $1
    do
        docker service rm ${SERVICE} &> /dev/null &
        display_stop_service ${SERVICE}
    done
}

# Used for start, stop, update, monitor and volumes scripts
help()
{
    echo -e "Illegal number of parameters. \nExample Usage: \n\t ocariot \e[1m<action> <option>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t start: operation to be realize.\
                         \n \t\t stop: Command utilized to stop services. Options as \e[4m--service and --clear-volumes\e[0m can be used.\
                         \n \t\t update: operation to be realize.\
                         \n \t\t backup: operation to be realize.\
                         \n \t\t restore: operation to be realize.\
             \n\t\e[1m<option>\e[0m: \n \t\t --service <[list of container name]>: specific volume used by the services.\
                         \n \t\t --clear-volumes <[list of volume name]>: specific volume used by the services.\
                         \n \t\t --time <[list of volume name]>: specific volume used by the services. \
                         \n \t\t --expression <[list of volume name]>: specific volume used by the services."
    exit 1
}
