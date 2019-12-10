#!/usr/bin/env bash

clear_volumes()
{
    grep -P '(?<=ocariot-).*(?=-data)' docker-compose.yml \
     | sed 's/\( \|name:\)//g' \
     | awk '{system("docker volume rm -f "$1)}'
}

help()
{
    echo -e "Illegal number of parameters. \nExample Usage: \n\t sudo ./stop <STACK_NAME> <OPTION>"
    echo -e "<OPTION>: \n \t -clear-volumes: remove all volume used by the services"
    exit
}

docker stack ps $1 > /dev/null 2>&1

if [ "$?" -ne 0 ]; then
    echo "$1 stack services not initialized"
    exit
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    help
fi

if [ "$#" -eq 2 ] && [ "$2" != "-clear-volumes" ]; then
    help
fi

# Stopping the ocariot stack services  that being run
docker stack rm $1 > /dev/null 2>&1

# Verifying if the services was removed
printf "Stoping services"
RET=0
while [[ $RET -eq 0 ]]; do
    docker stack ps $1 > /dev/null 2>&1
    RET=$?
    sleep 3
    printf "."
done
printf "\n"

ps aux \
    | grep -w service_monitor.sh \
    | sed '/grep/d' \
    | awk '{system("kill -9 "$2)}'

rm $(pwd)/config/vault/.certs/* -f
rm $(pwd)/config/consul/.certs/* -f

# If "-clear-volumes" parameter was passed the
# volumes will be excluded
if [ "$2" = "-clear-volumes" ];then
    clear_volumes > /dev/null
fi
