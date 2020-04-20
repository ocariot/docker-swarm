#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

update_env()
{
  if [ -z "$(find ${INSTALL_PATH} -maxdepth 1 -name $1.example)" ];then
    return
  fi

  if [ -z "$(find ${INSTALL_PATH} -maxdepth 1 -name $1)" ];then
    return
  fi

  cp ${INSTALL_PATH}/$1.example ${INSTALL_PATH}/$1.tmp

  VARIABLES=$(cat ${INSTALL_PATH}/$1.example | grep -vP '^#' | sed '/^$/d;s/=.*//g')
  for VAR in ${VARIABLES};do
    NEW_VARIABLE=$(grep -P "^${VAR}=" ${INSTALL_PATH}/$1)
    if [ "${NEW_VARIABLE}" ];then
      NEW_VARIABLE=$(echo "${NEW_VARIABLE}" | sed 's/\//\\\//g')
      sed -i "s/^${VAR}=.*/${NEW_VARIABLE}/g" ${INSTALL_PATH}/$1.tmp
    fi
  done

  rm -f ${INSTALL_PATH}/$1
  mv -f ${INSTALL_PATH}/$1.tmp ${INSTALL_PATH}/$1
}

get_last_tag()
{
   JSON=$(curl -s https://api.github.com/repos/ocariot/docker-swarm/releases/latest)
   echo ${JSON} | grep -oP '(?<="tag_name": ")[^"]*'
}

VALIDATING_OPTIONS=$(echo $@ | sed 's/ /\n/g' | grep -Pv "\-\-version.*" | grep '\-\-')

CHECK_VERSION_PARAMETER=$(echo $@ | grep -wo '\-\-version')
VERSION_VALUE=$(echo $@ | grep -o -P '(?<=--version ).*' | sed 's/--.*//g')

if ([ "$1" != "--version" ] && [ "$1" != "" ]) \
    || [ ${VALIDATING_OPTIONS} ] \
    || ([ ${CHECK_VERSION_PARAMETER} ] && [ "$(echo ${VERSION_VALUE} | wc -w)" != 1 ]); then

    ocariot_help
fi

if [ "${CHECK_VERSION_PARAMETER}" ];then
  TARGET=${VERSION_VALUE}
else
  TARGET=$(get_last_tag)
fi

VALIDATION=$(echo ${TARGET} | grep -wP '^[0-9].[0-9].[0-9]$')

if [ -z "${VALIDATION}" ]; then
  echo "Invalid version."
  exit
fi

FEATURE=$(echo ${TARGET} | sed 's/\./ /g' | awk '{print $2}')

if [ ${FEATURE} -lt 2 ]; then
  echo "Versions prior to 1.2.0 do not support the update operation".
  exit
fi

ACTUAL_VERSION=$(git -C ${INSTALL_PATH} describe --tags --abbrev=0)

sudo git -C ${INSTALL_PATH} reset --hard HEAD &> /dev/null
sudo git -C ${INSTALL_PATH} fetch &> /dev/null
sudo git -C ${INSTALL_PATH} checkout "tags/${TARGET}" &> /dev/null

if [ ${TARGET} = $(git -C ${INSTALL_PATH} describe --tags --abbrev=0) ];then
  if [ "${ACTUAL_VERSION}" != ${TARGET} ];then
    stop_process "ocariot_watchdog.sh"
    start_watchdog
  fi
  update_env ${ENV_OCARIOT}
  update_env ${ENV_MONITOR}
  echo "OCARIoT Project updated successfully!"
else
  echo "OCARIoT Project wasn't updated with success!"
fi
