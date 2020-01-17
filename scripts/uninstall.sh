#!/usr/bin/env bash

INSTALL_PATH="/opt/docker-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

isInstalled()
{
    ls /usr/local/bin/ocariot  &> /dev/null
    RET_OCARIOT_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_OCARIOT_PROJECT=$?

    RET_CRONTAB_MONITOR=$(crontab -u ${SUDO_USER} -l | grep -w "${MONITOR_COMMAND}")
    RET_CRONTAB_BKP=$(crontab -u ${SUDO_USER} -l | grep -w "${BKP_COMMAND}")

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

if [ "$#" -ne 0 ]; then
    help
    exit
fi

MONITOR_COMMAND="service_monitor.sh"
BKP_COMMAND="ocariot backup"

sudo rm -f /usr/local/bin/ocariot
( crontab -u ${SUDO_USER} -l | sed "/${MONITOR_COMMAND}/d"; ) | crontab -u ${SUDO_USER} -
( crontab -u ${SUDO_USER} -l | sed "/${BKP_COMMAND}/d"; ) | crontab -u ${SUDO_USER} -
sudo rm -fR ${INSTALL_PATH}

STATUS=$(isInstalled)
if ! ${STATUS}; then
  echo "Uninstall realized with success!"
else
  echo "Uninstall wasn't realized with success!"
fi