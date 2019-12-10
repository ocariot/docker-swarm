#!/usr/bin/env bash

INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"

STACK_NAME="ocariot"

clear_volumes()
{
    grep -P '(?<=ocariot-).*(?=-data)' ${INSTALL_PATH}/docker-compose.yml \
     | sed 's/\( \|name:\)//g' \
     | awk '{system("docker volume rm -f "$1)}'
}

help()
{
    echo -e "Illegal number of parameters. \nExample Usage: \n\t sudo ./stop <STACK_NAME> <OPTION>"
    echo -e "<OPTION>: \n \t -clear-volumes: remove all volume used by the services"
    exit
}

docker stack ps ${STACK_NAME} > /dev/null 2>&1

if [ "$?" -ne 0 ]; then
    echo "$1 stack services not initialized"
    exit
fi

if [ "$#" -gt 1 ]; then
    help
fi

if [ "$#" -eq 1 ] && [ "$1" != "-clear-volumes" ]; then
    help
fi

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

ps aux \
    | grep -w service_monitor.sh \
    | sed '/grep/d' \
    | awk '{system("kill -9 "$2)}'

rm ${INSTALL_PATH}/config/vault/.certs/* -f
rm ${INSTALL_PATH}/config/consul/.certs/* -f

# If "-clear-volumes" parameter was passed the
# volumes will be excluded
if [ "$1" = "-clear-volumes" ];then
    clear_volumes > /dev/null
fi
