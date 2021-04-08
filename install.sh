#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"

version()
{
  echo "1.7.4"
}

isInstalled()
{
    ls /usr/local/bin/ocariot  &> /dev/null
    RET_OCARIOT_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_OCARIOT_PROJECT=$?

    RET_CRONTAB_COMMAND=$(crontab -u ${USER} -l | grep -w "${WATCHDOG_COMMAND}")

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
    git clone https://github.com/ocariot/docker-swarm ${INSTALL_PATH} > /dev/null
    git -C ${INSTALL_PATH} checkout "tags/$(version)" > /dev/null
fi

WATCHDOG_COMMAND="ocariot_watchdog.sh"

STATUS=$(isInstalled)
if ${STATUS}; then
    echo "OCARIoT Project already installed!"
    exit
fi

if [ ! "$(find /usr/local/bin -maxdepth 1 -name ocariot)" ]; then
    sudo ln -s ${INSTALL_PATH}/ocariot /usr/local/bin/ocariot
    sudo chmod +x /usr/local/bin/ocariot
fi

CRONTAB_COMMAND=$(echo -e "@reboot ${INSTALL_PATH}/scripts/${WATCHDOG_COMMAND} >> /tmp/ocariot_watchdog.log &")

( crontab -u ${USER} -l; echo "${CRONTAB_COMMAND}" ) | crontab -u ${USER} -

STATUS=$(isInstalled)
if ${STATUS}; then
    echo "****OCARIoT Project was installed with success!****"
else
    echo "OCARIoT Project wasn't installed with success!"
fi
