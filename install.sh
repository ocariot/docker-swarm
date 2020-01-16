#!/usr/bin/env bash

#INSTALL_PATH="$(realpath $0 | grep .*docker-swarm -o)"
INSTALL_PATH="/opt/docker-swarm"

isInstalled()
{
    ls /usr/local/bin/ocariot  &> /dev/null
    RET_OCARIOT_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_OCARIOT_PROJECT=$?

    RET_CRONTAB_COMMAND=$(crontab -u ${SUDO_USER} -l | grep -w "${MONITOR_COMMAND}")

    if [ "${RET_CRONTAB_COMMAND}" ] &&
      [ ${RET_OCARIOT_COMMAND} = 0 ] &&
      [ ${RET_OCARIOT_PROJECT} = 0 ]; then
        echo "true"
        exit
    fi
    echo "false"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

if [ "$#" -ne 0 ]; then
    echo -e "Illegal parameters."
    exit
fi

ls ${INSTALL_PATH} &> /dev/null
if [ "$?" != "0" ];then
    sudo git clone https://github.com/ocariot/docker-swarm ${INSTALL_PATH} &> /dev/null
fi

MONITOR_COMMAND="service_monitor.sh"

ls /usr/local/bin/ocariot &> /dev/null
if [ "$?" = "0" ];then
    echo "OCARIoT Project already installed!"
    exit
fi

if [ ! "$(find /usr/local/bin -maxdepth 1 -name ocariot)" ]; then
    sudo ln -s ${INSTALL_PATH}/ocariot /usr/local/bin/ocariot
    sudo chmod +x /usr/local/bin/ocariot
fi

CRONTAB_COMMAND=$(echo -e "@reboot ${INSTALL_PATH}/scripts/${MONITOR_COMMAND} >> /tmp/ocariot_monitor_service.log &")

( crontab -u ${SUDO_USER} -l; echo "${CRONTAB_COMMAND}" ) | crontab -u ${SUDO_USER} -

STATUS=$(isInstalled)
if ${STATUS}; then
    echo "****OCARIoT Project was installed with success!****"
else
    echo "OCARIoT Project wasn't installed with success!"
fi