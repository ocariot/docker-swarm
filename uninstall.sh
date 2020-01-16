#!/usr/bin/env bash

INSTALL_PATH="/opt/docker-swarm"

isInstalled()
{
    ls /usr/local/bin/ocariot  &> /dev/null
    RET_OCARIOT_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_OCARIOT_PROJECT=$?

    RET_CRONTAB_COMMAND=$(crontab -u ${SUDO_USER} -l | grep -w "${MONITOR_COMMAND}")

    if [ ! "${RET_CRONTAB_COMMAND}" ] &&
      [ ! ${RET_OCARIOT_COMMAND} = 0 ] &&
      [ ! ${RET_OCARIOT_PROJECT} = 0 ]; then
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
    echo -e "Illegal parameters."
    exit
fi

MONITOR_COMMAND="service_monitor.sh"

sudo rm -f /usr/local/bin/ocariot
( crontab -u ${SUDO_USER} -l | sed "/${MONITOR_COMMAND}/d"; ) | crontab -u ${SUDO_USER} -
sudo rm -fR ${INSTALL_PATH}

RET=$(! ls /usr/local/bin/ocariot  &> /dev/null && \
  crontab -u ${SUDO_USER} -l | grep -w "${MONITOR_COMMAND}")

STATUS=$(isInstalled)
if ! ${STATUS}; then
  echo "Uninstall realized with success!"
else
  echo "Uninstall wasn't realized with success!"
fi