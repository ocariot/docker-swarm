#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

check_crontab()
{
    RET_CRONTAB_COMMAND=$(crontab -u ${USER} -l | grep -F "$1")

    if [ "${RET_CRONTAB_COMMAND}" ]; then
        echo "enable"
    else
        echo "disable"
    fi
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

validate_file_path()
{
  ls $1 &> /dev/null
  if [ $? != 0 ]; then
    echo "Path $1 not found!"
  fi
}

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' \
  | grep -P "(\-\-services|\-\-time|\-\-expression|\-\-path|\-\-keys).*" -v | grep '\-\-')

CHECK_NAME_PARAMETER=$(echo $@ | grep -wo '\-\-services')
CONTAINERS_BKP=$(echo $@ | grep -o -P '(?<=--services ).*' | sed "s/--.*//g")

CHECK_BKP_DIRECTORY_PARAMETER=$(echo $@ | grep -wo '\-\-path')
BKP_DIRECTORY=$(echo $@ | grep -o -P '(?<=--path ).*' | sed "s/--.*//g")

CHECK_TIME_PARAMETER=$(echo $@ | grep -wo '\-\-time')
RESTORE_TIME=$(echo $@ | grep -o -P '(?<=--time ).*' | sed 's/--.*//g')

CHECK_AUTO_BKP_PARAMETER=$(echo $@ | grep -wo '\-\-expression')
EXPRESSION_BKP=$(echo "$@" | grep -o -P '(?<=--expression ).*' | sed 's/--.*//g')

if ([ "$1" != "backup" ] && [ "$1" != "restore" ]) \
    || ([ "$2" != "--services" ] && [ "$2" != "--time" ] && [ "$2" != "--keys" ] && \
       [ "$2" != "--expression" ] && [ "$2" != "--path" ] && [ "$2" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_NAME_PARAMETER} ] && [ "${CONTAINERS_BKP}" = "" ]) \
    || ([ ${CHECK_BKP_DIRECTORY_PARAMETER} ] && [ "$(validate_file_path ${BKP_DIRECTORY})" != "" ]) \
    || ([ ${CHECK_AUTO_BKP_PARAMETER} ] && [ "${EXPRESSION_BKP}" = "" ]) \
    || ([ ${CHECK_TIME_PARAMETER} ] && [ "$(echo ${RESTORE_TIME} | wc -w)" != 1 ]); then
    monitor_help
fi

if [ ! ${CHECK_BKP_DIRECTORY_PARAMETER} ]; then
    BKP_DIRECTORY="$(pwd)"
fi

if [ ${RESTORE_TIME} ]; then
    RESTORE_TIME="--time ${RESTORE_TIME}"
fi

COMMAND="backup"
BACKUP_VOLUME_PROPERTY=""
SOURCE_VOLUME_PROPERTY=":ro"

if [ "$1" = "restore" ]; then
    COMMAND="restore ${RESTORE_TIME}"
    BACKUP_VOLUME_PROPERTY=":ro"
    SOURCE_VOLUME_PROPERTY=""
fi

if ([ ${COMMAND} = "backup" ] && [ ${CHECK_TIME_PARAMETER} ]) \
    || ([ ${COMMAND} = "restore" ] && [ ${CHECK_AUTO_BKP_PARAMETER} ]);then
    monitor_help
fi

if [ ${CHECK_AUTO_BKP_PARAMETER} ];then

    CRONTAB_COMMAND="${EXPRESSION_BKP} ${INSTALL_PATH}/ocariot monitor ${COMMAND} ${CONTAINERS_BKP} --path ${BKP_DIRECTORY} >> /tmp/ocariot_monitor_backup.log"

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
        crontab -u ${USER} -l
        echo "Backup is already scheduled"
        exit
    fi
    ( crontab -u ${USER} -l; echo "${CRONTAB_COMMAND}" ) | crontab -u ${USER} -

    STATUS=$(check_crontab "${CRONTAB_COMMAND}")

    if [ "${STATUS}" = "enable" ];then
        crontab -u ${USER} -l
        echo "Backup schedule successful!"
    else
        echo "Unsuccessful backup schedule!"
    fi

    exit
fi

VOLUMES_BKP=""
RUNNING_SERVICES=""

MONITOR_VOLUMES=$(cat ${INSTALL_PATH}/docker-monitor-stack.yml | grep -P "name: ocariot.*data" | sed 's/\(name:\| \)//g')
EXPRESSION_GREP=$(echo "${MONITOR_VOLUMES}" | sed 's/ /|/g')

# Verifying if backup folder exist
if [  "$1" = "restore" ];
then
    DIRECTORIES=$(ls ${BKP_DIRECTORY} 2> /dev/null)
    if [ $? -ne 0 ];then
        echo "Directory not found."
        exit
    fi

    EXIST_BKP=false
    for DIRECTORY in ${DIRECTORIES}; do
      if [ "$(echo "${MONITOR_VOLUMES}" | grep -w "${DIRECTORY}")" ]; then
        EXIST_BKP=true
        break
      fi
    done

    if ! ${EXIST_BKP}; then
      echo "No container backup was found"
      exit
    fi
fi

if [ "${CONTAINERS_BKP}" = "" ]; then
	if [ "$1" = "backup" ];
    then
        CONTAINERS_BKP=$(docker volume ls --format "{{.Name}}" \
            | grep -oE "${EXPRESSION_GREP}" \
            | sed 's/\(ocariot-monitor-\|-data\)//g')
    else
        CONTAINERS_BKP=$(ls ${BKP_DIRECTORY} \
            | grep -oE "${EXPRESSION_GREP}" \
            | sed 's/\(ocariot-monitor-\|-data\)//g')
    fi
fi

CONTAINERS_BKP=$(echo ${CONTAINERS_BKP} | tr " " "\n" | sort -u)

for CONTAINER_NAME in ${CONTAINERS_BKP};
do
    SERVICE_NAME=$(docker stack services {MONITOR_STACK_NAME} \
        --format "{{.Name}}" \
        | grep -w ${MONITOR_STACK_NAME}_.*${CONTAINER_NAME})
    RUNNING_SERVICES="${RUNNING_SERVICES} ${SERVICE_NAME}"

    if [ "$1" = "backup" ];
    then
        MESSAGE="Volume BKP ${CONTAINER_NAME} not found!"
        VOLUME_NAME=$(docker volume ls \
            --format "{{.Name}}" \
            | grep -oE "${EXPRESSION_GREP}" \
            | grep -w ${CONTAINER_NAME})
    else
        MESSAGE="Not found ${CONTAINER_NAME} volume!"
        VOLUME_NAME=$(ls ${BKP_DIRECTORY} \
            | grep -oE "${EXPRESSION_GREP}" \
            | grep -w ${CONTAINER_NAME})
    fi

    if [ -z "${VOLUME_NAME}" ]
    then
        echo "${MESSAGE}"
        exit
    fi
    VOLUMES_BKP="${VOLUMES_BKP} ${VOLUME_NAME}"
done

if [ -z "${VOLUMES_BKP}" ];
then
    echo "Not found ${MONITOR_STACK_NAME} volumes!"
    exit
fi

if [ ! $(find /tmp -maxdepth 1 -name cache-ocariot-monitor) ]
then
    mkdir /tmp/cache-ocariot-monitor
fi

INCREMENT=1
for VOLUME in ${VOLUMES_BKP};
do
    VOLUMES="${VOLUMES} -v ${VOLUME}:/source/${VOLUME}${SOURCE_VOLUME_PROPERTY}"
    VOLUMES_CACHE="${VOLUMES_CACHE} -v /tmp/cache-ocariot-monitor/${VOLUME}:/volumerize-cache/${VOLUME}"
    ENVIRONMENTS_SOURCE="${ENVIRONMENTS_SOURCE} -e VOLUMERIZE_SOURCE${INCREMENT}=/source/${VOLUME}"
    ENVIRONMENTS_TARGET="${ENVIRONMENTS_TARGET} -e VOLUMERIZE_TARGET${INCREMENT}=file:///backup/${VOLUME}"
    ENVIRONMENTS_CACHE="${ENVIRONMENTS_CACHE} -e VOLUMERIZE_CACHE${INCREMENT}=/volumerize-cache/${VOLUME}"
    INCREMENT=$((INCREMENT + 1))
done

remove_services "${RUNNING_SERVICES}"

if [ "$1" = "restore" ];
then
    remove_volumes "${VOLUMES_BKP}"
fi

docker run --rm \
    --name volumerize \
    ${VOLUMES} \
    ${VOLUMES_CACHE} \
    -v ${BKP_DIRECTORY}:/backup${BACKUP_VOLUME_PROPERTY} \
    ${ENVIRONMENTS_SOURCE} \
    ${ENVIRONMENTS_TARGET} \
    blacklabelops/volumerize /bin/bash -c "${COMMAND}" \
    && PROCESS_BKP="OK"

if [ "${PROCESS_BKP}" = "OK" ]; then
  RUNNING_SERVICES=$(echo ${RUNNING_SERVICES} | sed 's/ //g' )

  if [ "${RUNNING_SERVICES}" ]; then
    ${INSTALL_PATH}/scripts/monitor/start.sh
  fi
fi

rm -rf  /tmp/cache-ocariot-monitor