#!/usr/bin/env bash

INSTALL_PATH="/opt/ocariot-swarm"

# Used for start, update and volumes scripts
set_variables_environment()
{
    # Verifying the existence of .env file
    if [ ! $(find ${INSTALL_PATH} -name .env) ]
    then
       cp ${INSTALL_PATH}/.env.example ${INSTALL_PATH}/.env
       editor ${INSTALL_PATH}/.env
    fi

    # Executing .env to capture environment variable defined in it
    set -a && . ${INSTALL_PATH}/.env && set +a
}

# Used for start, update and volumes scripts
display_stop_service()
{
    # Verifying if the services was removed
    echo "Stoping service: $1"
    RET=1
    while [[ $RET -ne 0 ]]; do
        RET=$(docker service ls --filter "name=$1" | tail -n +2 | wc -l)
    done
}

# Used for stop and update scripts. Depend of display_stop_service function
remove_services()
{
    for SERVICE in $1
    do
        docker service rm ${SERVICE} &> /dev/null &
        display_stop_service ${SERVICE}
    done
}

ocariot_help()
{
    echo -e "Illegal parameters. \nExample Usage: \n\t sudo ocariot \e[1m<action>\e[0m "
    echo -e "\t\e[1m<action>\e[0m: \n \t\t \e[7muninstall\e[27m: operation to be realize.\
      \n \t\t \e[7mupdate\e[27m: command used to update the ocariot software. \
      \n \t\t \e[7mstack\e[27m: operation to be realize.\
      \n \t\t \e[7mmonitor\e[27m: operation to be realize."
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
		of services, use the \e[4m--services\e[0m option. If the \e[4m--path\e[0m option is not set, the backup will be  \
		saved to the current location. It is also possible to schedule the backup by passing a crontab expression in the \
		value of the \e[4m--expression\e[0m option. \
			\n \t\t \e[7mrestore\e[27m: restore all services in the ocariot stack. If you want to restore a specific set of \
		services, use the \e[4m--services\e[0m option. If the \e[4m--path\e[0m option is not set, the restore command \
		will search for backup files in the current location. \
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
			\n \t\t \e[7m--path <value>\e[27m: parameter used to specify the path where the backup will be saved or where \
		the backup files will be searched for restoring from a previous backup performed. \
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
the health of containers."
    exit 1
}