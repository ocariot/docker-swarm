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
    RET_OCARIOT_BKP_CRONTAB=$(crontab -u ${USER} -l | grep -w "${OCARIOT_BKP_COMMAND}")
    RET_MONITOR_BKP_CRONTAB=$(crontab -u ${USER} -l | grep -w "${MONITOR_BKP_COMMAND}")

    if [ ! "${RET_CRONTAB_MONITOR}" ] &&
      [ ! "${RET_OCARIOT_BKP_CRONTAB}" ] &&
      [ ! "${RET_MONITOR_BKP_CRONTAB}" ] &&
      [ ${RET_OCARIOT_COMMAND} != 0 ] &&
      [ ${RET_OCARIOT_PROJECT} != 0 ]; then
        echo "false"
        exit
    fi
    echo "true"
}

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -P "\-\-clear\-volumes.*" -v | grep '\-\-')

CHECK_CLEAR_VOLUMES_PARAMETER=$(echo $@ | grep -wo '\-\-clear\-volumes')
CLEAR_VOLUMES_VALUE=$(echo $@ | grep -o -P '(?<=--clear-volumes ).*' | sed 's/--.*//g')

if ([ "$1" != "--clear-volumes" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_CLEAR_VOLUMES_PARAMETER} ] && [ "$(echo ${CLEAR_VOLUMES_VALUE} | wc -w)" != 0 ]); then

    ocariot_help
fi

WATCHDOG_COMMAND="ocariot_watchdog.sh"
OCARIOT_BKP_COMMAND="ocariot stack backup"
MONITOR_BKP_COMMAND="ocariot monitor backup"

if ([ "$(docker stack ls | grep ${OCARIOT_STACK_NAME})" ] || [ "${CHECK_CLEAR_VOLUMES_PARAMETER}" ]); then
  ${INSTALL_PATH}/scripts/stack/stop.sh ${CHECK_CLEAR_VOLUMES_PARAMETER}
fi

if ([ "$(docker stack ls | grep ${MONITOR_STACK_NAME})" ] || [ "${CHECK_CLEAR_VOLUMES_PARAMETER}" ]); then
  ${INSTALL_PATH}/scripts/monitor/stop.sh ${CHECK_CLEAR_VOLUMES_PARAMETER}
fi

sudo rm -f /usr/local/bin/ocariot
( crontab -u ${USER} -l | sed "/${WATCHDOG_COMMAND}/d"; ) | crontab -u ${USER} -
( crontab -u ${USER} -l | sed "/${OCARIOT_BKP_COMMAND}/d"; ) | crontab -u ${USER} -
( crontab -u ${USER} -l | sed "/${MONITOR_BKP_COMMAND}/d"; ) | crontab -u ${USER} -
sudo rm -fR ${INSTALL_PATH}
sudo rm -f /tmp/ocariot_watchdog.log /tmp/ocariot_backup.log
sudo rm -rf /tmp/cache-ocariot*

stop_watchdog

STATUS=$(isInstalled)
if ! ${STATUS}; then
  echo "Uninstall realized with success!"
else
  echo "Uninstall wasn't realized with success!"
fi