#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

isInstalled()
{
    ls /usr/local/bin/ocariot  &> /dev/null
    RET_OCARIOT_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_OCARIOT_PROJECT=$?

    RET_CRONTAB_MONITOR=$(crontab -u ${USER} -l | grep -w "${WATCHDOG_COMMAND}")
    RET_CRONTAB_BKP=$(crontab -u ${USER} -l | grep -w "${BKP_COMMAND}")

    if [ ! "${RET_CRONTAB_MONITOR}" ] &&
      [ ! "${RET_CRONTAB_BKP}" ] &&
      [ ${RET_OCARIOT_COMMAND} != 0 ] &&
      [ ${RET_OCARIOT_PROJECT} != 0 ]; then
        echo "false"
        exit
    fi
    echo "true"
}


if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "\-\-clear\-volumes.*" -v | grep '\-\-')

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/--.*//g')

if ([ "$1" != "--clear-volumes" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_CLEAR_VOLUMES_PARAMETER} ] && [ "$(echo ${CLEAR_VOLUMES_VALUE} | wc -w)" != 0 ]); then

    ocariot_help
fi

WATCHDOG_COMMAND="ocariot_watchdog.sh"
BKP_COMMAND="ocariot stack backup"

docker stack ps ${OCARIOT_STACK_NAME} > /dev/null 2>&1
STATUS_OCARIOT_STACK=$?

if ([ "${STATUS_OCARIOT_STACK}" -eq 0 ] || [ "${CHECK_CLEAR_VOLUMES_PARAMETER}" ]); then
  ${INSTALL_PATH}/scripts/stack/stop.sh ${CHECK_CLEAR_VOLUMES_PARAMETER}
fi

sudo rm -f /usr/local/bin/ocariot
( crontab -u ${USER} -l | sed "/${WATCHDOG_COMMAND}/d"; ) | crontab -u ${USER} -
( crontab -u ${USER} -l | sed "/${BKP_COMMAND}/d"; ) | crontab -u ${USER} -
sudo rm -fR ${INSTALL_PATH}
sudo rm -f /tmp/ocariot_watchdog.log /tmp/ocariot_backup.log

STATUS=$(isInstalled)
if ! ${STATUS}; then
  echo "Uninstall realized with success!"
else
  echo "Uninstall wasn't realized with success!"
fi