#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"
source ${INSTALL_PATH}/scripts/general_functions.sh

update_env()
{
  if [ ! $(find ${INSTALL_PATH} -name $1.example) ];then
    return
  fi

  if [ ! $(find ${INSTALL_PATH} -name $1) ];then
    return
  fi

  cp $1.example $1.tmp

  VARIABLES=$(cat $1.example | grep -vP '^#' | sed '/^$/d;s/=.*//g')
  for VAR in ${VARIABLES};do
    NEW_VARIABLE=$(grep -P "^${VAR}=" $1)
    if [ "${NEW_VARIABLE}" ];then
      NEW_VARIABLE=$(echo ${NEW_VARIABLE} | sed 's/\//\\\//g')
      sed -i "s/^${VAR}=.*/${NEW_VARIABLE}/g" $1.tmp
    fi
  done

  rm -f $1
  mv -f $1.tmp $1
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

TARGET=$(get_last_tag)
if [ "${CHECK_VERSION_PARAMETER}" ];then
  TARGET=${VERSION_VALUE}
fi

echo ${TARGET}

sudo git -C ${INSTALL_PATH} reset --hard HEAD &> /dev/null
sudo git -C ${INSTALL_PATH} fetch &> /dev/null
sudo git -C ${INSTALL_PATH} checkout "tags/${TARGET}" &> /dev/null

if [ ${TARGET} = $(git -C ${INSTALL_PATH} describe --tags --abbrev=0) ];then
  update_env ${ENV_OCARIOT}
  update_env ${ENV_MONITOR}
  echo "OCARIoT Project updated successfully!"
else
  echo "OCARIoT Project wasn't updated with success!"
fi
