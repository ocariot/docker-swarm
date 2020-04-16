#!/usr/bin/env bash

###########################################################################################################
###########################################  GENERAL VARIABLES ############################################
###########################################################################################################

INSTALL_PATH="/opt/ocariot-swarm"
OCARIOT_STACK_NAME="ocariot"
MONITOR_STACK_NAME="ocariot_monitor"
ENV_OCARIOT=".env"
ENV_MONITOR=".env.monitor"
NETWORK_NAME="ocariot"
BACKUP_CONTAINER_NAME="volumerize"
CLOUD_TARGET=$(echo ${CLOUD_TARGET} | sed 's/\/$//g')
OCARIOT_CREDS_DRIVER="ocariot-credentials-data"
MONITOR_CREDS_DRIVER="ocariot-monitor-credentials-data"

###########################################################################################################
###########################################  GENERAL FUNCTIONS ############################################
###########################################################################################################

start_watchdog()
{
  ${INSTALL_PATH}/scripts/ocariot_watchdog.sh >> /tmp/ocariot_watchdog.log &
}

stop_watchdog()
{
  ps aux \
    | grep -w ocariot_watchdog.sh \
    | sed '/grep/d' \
    | awk '{system("kill -9 "$2)}'
}

create_network()
{
  echo "Trying create network."
  if [ -z "$(docker network ls --format={{.Name}} | grep -P "^${NETWORK_NAME}$")" ]; then
    docker network create --opt encrypted --driver overlay --attachable "${NETWORK_NAME}" &> /dev/null
    if [ $? != 0 ]; then
      echo "It was not possible to create the network. Probably another stack has already created the ocariot network."
    fi
  fi
}

delete_network()
{
  echo "Trying remove network."
  if [ "$(docker network ls --format={{.Name}} | grep -P "^${NETWORK_NAME}$")" ]; then
    docker network rm "${NETWORK_NAME}" &> /dev/null
    if [ $? != 0 ]; then
      echo "It was not possible to remove the network. Probably another stack is using the ocariot network."
    fi
  fi
}

# Used for stack start and monitor start
set_variables_environment()
{
    # Verifying the existence of .env file
    if [ ! $(find ${INSTALL_PATH} -name $1) ]
    then
       cp ${INSTALL_PATH}/$1.example ${INSTALL_PATH}/$1
       editor ${INSTALL_PATH}/$1
    fi

    # Executing .env to capture environment variable defined in it
    set -a && . ${INSTALL_PATH}/$1 && set +a
}

# Used for start, update and volumes scripts
display_stop_service()
{
    # Verifying if the services was removed
    printf "Stoping $1 service"
    while [[ $(docker container ls --filter "name=$1" | tail -n +2 | wc -l) -ne 0 ]]; do
        printf '.'
        sleep 2
    done
    printf '\n'
}

# Used for stop and update scripts. Depend of display_stop_service function
remove_services()
{
    docker service rm $1 &> /dev/null
    for SERVICE in $1
    do
        display_stop_service ${SERVICE}
    done
}

###########################################################################################################
#############################################  HELP FUNCTIONS #############################################
###########################################################################################################

ocariot_help()
{
    echo -e "Illegal parameters. \nExample Usage: \n\t sudo ocariot \e[1m<action>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t \e[7muninstall\e[27m: command to uninstall the ocariot software. \
It is also possible to delete all volumes used on the ocariot platform, passing the \
option of \e[4m--clear-volumes\e[0m.\
      \n \t\t \e[7mupdate\e[27m: command used to update the ocariot software. It's possible specify the version using \e[4m--version\e[0m option\
      \n \t\t \e[7mstack\e[27m: operations performed on the ocariot stack. Use \e[4msudo ocariot stack help\e[0m for more information. \
      \n \t\t \e[7mmonitor\e[27m: operations performed on the ocariot monitor stack. Use \e[4msudo ocariot monitor help\e[0m for more information. \
      \n \t\t \e[7mversion\e[27m: command used to view the current version of the installed OCARIoT software. \
      \n\t\e[1m<option>\e[0m: \n \t\t \e[7m--clear-volumes\e[27m: parameter used to clear all volumes used on the ocariot platform. \
      \n \t\t \e[7m--version\e[27m: Parameter defines the version to which you want to migrate the software. For example: \e[4msudo ocariot update --version 1.3.3\e[0m"
    exit 1
}

stack_help()
{
    echo -e "Illegal parameters. \nExample Usage: \n\t sudo ocariot stack \e[1m<action> <option>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t \e[7mstart\e[27m: initialize all services of stack ocariot. \
			\n \t\t \e[7mstop\e[27m: stop all ocariot stack services. If you want to stop a specific set of services, use the \
\e[4m--services\e[0m option. It is also possible to delete all volumes used on the ocariot platform, passing the \
option of \e[4m--clear-volumes\e[0m. \
			\n \t\t \e[7mbackup\e[27m: backs up all services in the ocariot stack. If you want to make back up a specific set \
of services, use the \e[4m--services\e[0m option.  It is also possible to schedule the backup by passing a crontab \
expression in the value of the \e[4m--expression\e[0m option. \
			\n \t\t \e[7mrestore\e[27m: restore all services in the ocariot stack. If you want to restore a specific set of \
services, use the \e[4m--services\e[0m option. \
			\n \t\t \e[7mupdate-images\e[27m: updates the microservice images. If you want to update a specific set of \
services, use the \e[4m--services\e[0m option. \
			\n \t\t \e[7medit-config\e[27m: command used to edit platform settings. \
		\n\t\e[1m<option>\e[0m: \n \t\t \e[7m--services <[values>\e[27m: define a set of services passed to a command. \
			\n \t\t \e[7m--clear-volumes\e[27m: parameter used to clear all volumes used on the ocariot platform. \
			\n \t\t \e[7m--time <value>\e[27m: You can restore from a particular backup by adding a time parameter to the \
command restore. For example, using restore --time 3D at the end in the above command will restore a backup from \
3 days ago. See the Duplicity manual to view the accepted time formats \
(http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8). \
			\n \t\t \e[7m--keys <value>\e[27m: specifies the location of the file containing the encryption keys used by \
the vault. \
			\n \t\t \e[7m--expression <value>\e[27m: parameter used to define a crontab expression that will be performed \
hen scheduling the back up. The value of this option must be passed in double quotes. Example: sudo ocariot \
stack backup --expression \"0 3 * * *\""
    exit 1
}

monitor_help()
{
    echo -e "Illegal parameters. \nExample Usage: \n\t sudo ocariot monitor \e[1m<action>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t \e[7mstart\e[27m: command used to \e[33minitialize\e[0m the stack of \
services responsible for monitoring the health of containers.\
      \n \t\t \e[7mstop\e[27m: command used to \e[33mstop\e[0m the stack of services responsible for monitoring \
the health of containers.
      \n \t\t \e[7mbackup\e[27m: backs up all services in the ocariot_monitor stack. If you want to make back up a specific set \
of services, use the \e[4m--services\e[0m option. It is also possible to schedule the backup by passing a crontab \
expression in the \
value of the \e[4m--expression\e[0m option. \
			\n \t\t \e[7mrestore\e[27m: restore all services in the ocariot_monitor stack. If you want to restore a specific set of \
services, use the \e[4m--services\e[0m option. \
    \n\t\e[1m<option>\e[0m: \n \t\t \e[7m--services <[values>\e[27m: define a set of services passed to a command. \
			\n \t\t \e[7m--clear-volumes\e[27m: parameter used to clear all volumes used by monitor. \
			\n \t\t \e[7m--time <value>\e[27m: You can restore from a particular backup by adding a time parameter to the \
command restore. For example, using restore --time 3D at the end in the above command will restore a backup from \
3 days ago. See the Duplicity manual to view the accepted time formats \
(http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8). \
			\n \t\t \e[7m--expression <value>\e[27m: parameter used to define a crontab expression that will be performed \
hen scheduling the back up. The value of this option must be passed in double quotes. Example: sudo ocariot \
monitor backup --expression \"0 3 * * *\""
    exit 1
}

###########################################################################################################
###########################################  BACKUP FUNCTIONS #############################################
###########################################################################################################

check_crontab() {
	RET_CRONTAB_COMMAND=$(crontab -u "${USER}" -l | grep -F "$1")

	if [ "${RET_CRONTAB_COMMAND}" ]; then
		echo "enable"
	else
		echo "disable"
	fi
}

remove_volumes() {
	for VOLUME_NAME in $1; do

		VOLUME=$(docker volume ls --filter "name=${VOLUME_NAME}" --format {{.Name}})

		if [ -z "${VOLUME}" ]; then
			continue
		fi

		RET=1
		printf "Removing Volume: %s" "${VOLUME_NAME}"
		while [[ ${RET} -ne 0 ]]; do
			printf "."
			docker volume rm ${VOLUME_NAME} -f &>/dev/null
			RET=$?
		done
		printf "\n"
	done
}

validate_file_path() {
	ls $1 &>/dev/null
	if [ $? != 0 ] || [ -z "$1" ]; then
		echo "Path $1 not found!"
	fi
}

cloud_bkps() {
	docker run -t $1 --rm --name ${BACKUP_CONTAINER_NAME} \
		-v $2:/credentials \
		-e "VOLUMERIZE_SOURCE=/source" \
		-e "VOLUMERIZE_TARGET=${CLOUD_TARGET}" \
		-e "GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY}" \
		-e "AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY}" \
		blacklabelops/volumerize "${@:3}"
}

validate_bkp_target() {
	if [ -z "$(echo $1 | grep -P "$2")" ]; then
		echo "$3"
		exit
	fi
}

check_restore_target_config() {
	ERROR_MESSAGE="The CLOUD_TARGET variable does not correspond to the RESTORE_TARGET variable."

	case ${RESTORE_TARGET} in
	LOCAL)
		if [ -z "${LOCAL_TARGET}" ]; then
			echo "The LOCAL_TARGET environment variable have not been defined."
			exit
		fi
		ERROR_MESSAGE="The LOCAL_TARGET variable does not correspond to the RESTORE_TARGET variable."
		validate_bkp_target ${LOCAL_TARGET} "^/" "${ERROR_MESSAGE}"
		;;
	GOOGLE_DRIVE)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "CLOUD_TARGET" "${ERROR_MESSAGE}"
		;;
	AWS)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		;;
	*)
		echo "The value ${RESTORE_TARGET} in RESTORE_TARGET variable is not supported."
		exit
		;;
	esac
}

check_backup_target_config() {
	if [ -z "${CLOUD_TARGET}" ] && [ -z "${LOCAL_TARGET}" ]; then
		echo "No target defined."
		exit
	fi

	ERROR_MESSAGE="The value in CLOUD_TARGET variable is invalid."

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^gdocs")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
		CREDS_FILE_NAME="googledrive.cred"
		CREDS_FILE="$(cloud_bkps "" $1 find /credentials -name ${CREDS_FILE_NAME})"
		if [ -z "$(echo ${CREDS_FILE} | grep ${CREDS_FILE_NAME})" ]; then
			cloud_bkps "-i" $1 list
		fi
	fi

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^s3")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
	fi

	if [ "${LOCAL_TARGET}" ]; then
		ERROR_MESSAGE="The value in LOCAL_TARGET variable is invalid."
		validate_bkp_target ${LOCAL_TARGET} "^/" "${ERROR_MESSAGE}"
	fi
}

multi_backup_config() {
	cat >"$1" <<EOF
[
]
EOF

	if [ "${LOCAL_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >>$1
	fi

	if [ "${CLOUD_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >>$1
	fi

}

restore_config() {
	cat >"$1" <<EOF
[
]
EOF

	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >>$1
	else
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >>$1
	fi
}

backup_container_operation()
{
	docker container "$1" "${BACKUP_CONTAINER_NAME}" > /dev/null
}
