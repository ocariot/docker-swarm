# Docker Swarm - OCARIoT Production Deployment
[![License][license-image]][license-url] [![Commit][last-commit-image]][last-commit-url] [![Releases][releases-image]][releases-url] [![Contributors][contributors-image]][contributors-url] 

Repository with configuration files required for OCARIoT platform **deployment in production environment** using Docker Swarm.

## Main Features:
- **Simplified and automated startup through scripts.**
- **Vault:** 
  - Automatic startup and unlocking;
  - Creation of access tokens for internal services and creation of encryption keys;
  - Enable plugins for PSMDB, RabbitMQ and Certificates management.

- **PSMDB (MongoDB containers):**
  - Automatic communication with Vault to recover encryption keys, user and certificates;
  - Encryption at rest enabled;
  - SSL/TLS enabled;
  - Authentication enabled.

- **RabbitMQ (Message Bus):** 
  - Automatic communication with Vault to recover user and certificates;
  - SSL/TLS enabled;
  - Authentication enabled.
   
- **Microservices:** 
  - Automatic communication with Vault to retrieve databases access credentials and RabbitMQ, as well as certificates;
  - SSL/TLS enabled.

----

## Prerequisites
1. Linux _(Ubuntu 16.04+ recommended)_
2. Docker Engine 18.06.0+
   - Follow all the steps present in the [official documentation](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce).
3. Docker Compose 1.22.0+
   - Follow all the steps present in the [official documentation](https://docs.docker.com/compose/install/).
4. Make sure that Swarm is enabled by typing `docker system info`, and looking for a message `Swarm: active` _(you might have to scroll up a little)_.
   - If Swarm isn’t running, simply type `docker swarm init` at a shell prompt to set it up.
5. Valid SSL/TLS certificates issued by a valid certification authority (CA). You can get certified for your domain for free through [Let’s Encrypt](https://letsencrypt.org/).
6. Ensure that the secure_path variable in the _/etc/sudoers_ file contains the path _/usr/local/bin_.
7. Ensure that the `editor` command is configured with the standard editor used on the terminal. If not, add the editors used. Example, adding the `nano` editor: `sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nano 100`.
    - To choose the default editor use the command: `sudo update-alternatives --config editor`

## 1. Instalation
All software installation is performed using the following command:

```sh
curl -o- https://raw.githubusercontent.com/ocariot/docker-swarm/1.4.0/install.sh | sudo bash
```

```sh
wget -qO- https://raw.githubusercontent.com/ocariot/docker-swarm/1.4.0/install.sh | sudo bash
```


After the execution of this script has finished, the message `****OCARIoT Project was installed with success!****` will be displayed, thus demonstrating that the software installation was successful. Otherwise, the message to be displayed will be `OCARIoT Project wasn't installed with success!`.

If script execution is successful, the ocariot command will be recognized by bash:

![](https://i.imgur.com/2tEGTAP.png)

:pushpin: Note: The directory adopted for installing the software is a location that requires sudo privileges, therefore, for the execution of the ocariot command, the sudo prefix will always be necessary. For example: `sudo ocariot stack start`. 

## 2. Ocariot services stack

### 2.1 Set the environment variables
To ensure flexibility and increase the security of the platform, the OCARIoT services receive some parameters through environment variables, e.g. IPs, credentials (username and password), etc.

There are two ways to edit these environment variables. The first is during the first startup (`sudo ocariot stack start`), where the file containing these variables will be opened automatically with the standard editor. After making the necessary settings and saving the file, initialization will continue. 

On future start-ups, the settings file will not be opened automatically. Consequently, the second way aims to make subsequent editions possible, for which the following interface is reserved:

```sh
$ sudo ocariot stack edit-config
```

#### 2.1.1 External Service URL
Variables to define the URL of services to be exposed, such as Vault and RabbitMQ Management. This is useful for viewing data saved in Vault and managing the Message Bus.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `API_GATEWAY_HOSTNAME` |  API Gateway hostname. | `api.ocariot.com.br` |
| `VAULT_HOSTNAME` |  Vault HashiCorp hostname. | `vault.ocariot.com.br` |
| `RABBIT_MGT_HOSTNAME` |  RabbitMQ Management hostname. | `rabbit.ocariot.com.br` |
| `MONITOR_HOSTNAME` | Monitor/Grafana hostname. | `monitor.ocariot.com.br` |

#### 2.1.2 External Service Ports
Variables to define the ports of services to be exposed, such as API Gateway, Vault, and RabbitMQ Management.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `AG_PORT_HTTP` |  Port used by the API Gateway service to listen for HTTP request. Automatically redirects to HTTPS port. | `80` |
| `AG_PORT_HTTPS` | Port used by the API Gateway service to listen for HTTPS request. | `443` |


#### 2.1.3 Certificates/keys
Variables to define the ports of services to be exposed, such as API Gateway, Vault, and RabbitMQ Management.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `AG_KEY_PATH` | API Gateway private key. | `mycerts/privkey.pem` |
| `AG_CERT_PATH` | API Gateway domain certificate/public key. | `mycerts/fullchain.pem` |



#### 2.1.4 Data Sync Setup
Variables used by the Data Sync Agent microservice, responsible for data synchronization between Fitbit and OCARIoT platforms. This information is provided by Fitbit when registering an OAuth2 client. Please, **contact the partner responsible for microservice development to obtain the values for each variable.**

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `FITBIT_CLIENT_ID` | Client Id for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `11ABWZ` |
| `FITBIT_CLIENT_SECRET` |  Client Secret for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `1234ab56cd789123wzd123a` |
| `EXPRESSION_AUTO_SYNC` | Frequency time that the application will sync the users data in background according to the crontab expression. For example, the value `0 * * * *` means that synchronization will occur every hour. | `"0 * * * *"` |

#### 2.1.5 Authorization/Authentication Setup

Variables to define the administrator user's credentials the first time the platform is instantiated.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `ADMIN_USERNAME` | Username of the default admin user created automatically at the first time the OCARIoT platform is instantiated. | `admin` |
| `ADMIN_PASSWORD` | Password of the default admin user created automatically at the first time the OCARIoT platform is instatiated. | `admin` |

### 2.2 Building and Deploying the containers

#### 2.2.1 Start containers

To execute all the necessary commands to lift the entire stack of containers use the following interface:

```sh
$ sudo ocariot stack start
```

Lifting all containers may take a few seconds or a few minutes. When the entire stack has been successfully initialized, you will see the following message on the terminal: `Stack initialized successfully!!! :)` followed by the OCARIoT logo.

> :warning: **During the first boot, the encryption keys and root access token will be generated. This content will be made available in the *keys* file, which will be generated at the place of execution of the command currently described. This file is of fundamental importance for the restoration of backups.**
>
>:warning: **It is also noteworthy that these keys must be kept in an offline environment, considering that the leakage of such keys will result in an environment of high vulnerability.**

#### 2.2.2 Stop containers
To stop the stack, you can run the `stop` interface . This will cause all containers to be stopped. The volumes will remain intact.

```sh
$ sudo ocariot stack stop
```

*Optional parameters:*

- `--services <values>` - Defines a set of services to be stopped. The delimiter for specifying one more service is space. For example: `sudo ocariot stack stop --services account iot-tracking`;
- `--clear-volumes` - Argument used to remove all volumes. However, **be careful as the process is irreversible.**

#### 2.2.3 Backup

To perform the backup generation of all volumes used by the OCARIoT platform, the following interface is reserved:

```sh
$ sudo ocariot stack backup
```

:pushpin: Note: If they are running, the services that will participate in the backup operation will be temporarily stopped. At the end of the backup operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--services <values>` - Defines a set of services from which you want to generate the backup. The delimiter for specifying one more service is space. For example: `sudo ocariot stack backup --services account iot-tracking`;
- `--expression <values>` - Parameter used to define a crontab expression that will schedule the generation of a backup. The value of this option must be passed in double quotes. Example: `sudo ocariot stack backup --expression "0 3 * * *"`;
- `--path <values>` - Parameter used to specify the path where the backup will be saved. If this option is omitted, the backup files will be placed at the place of execution of the command currently described.

#### 2.2.4 Restore
In order to restore all backups of the volumes present in the current path, the following interface is reserved:

```sh
$ sudo ocariot stack restore
```

:pushpin: Note: If they are running, the services that will participate in the restore operation will be temporarily stopped. At the end of the restore operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--keys` - Specifies the location of the file containing the encryption keys and root token used by the vault. This file was generated at the first start of the OCARIoT stack using the command [`sudo ocariot stack start`](#3-Building-and-Deploying-the-containers). To restore only the cryptographic keys, the backup path must not have any backup files;
- `--path` - Parameter used to specify the path where the backup files will be searched for restoring from a previous backup performed. If this option is omitted, the backup files will be searched at the place of execution of the command currently described;
- `--services <values>` - Defines a set of services that will have their volumes restored. The delimiter for specifying one more service is space. For example: `sudo ocariot stack restore --services account iot-tracking`;
- `--time` - You can restore from a particular backup by adding a time parameter to the command restore. For example, using restore `--time 3D `at the end in the above command will restore a backup from 3 days ago. See the [Duplicity manual](http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8) to view the accepted time formats.

#### 2.2.5 Plataform Images Update

Interface used to update the docker images used by the OCARIoT microservices.

```sh
$ sudo ocariot stack update-images
```
*Optional parameters:*

- `--services <values>` - Defines a set of images of the services to be updated. The delimiter for specifying one more service is space. For example: `sudo ocariot stack update-images --services account iot-tracking`.

## 3. Health monitor services stack 

### 3.1 Set the environment variables
To ensure flexibility, the Health monitor services receive some parameters through environment variables, e.g. SMTP configurations, credentials (username and password), etc.

There are two ways to edit these environment variables. The first is during the first startup (`sudo ocariot monitor start`), where the file containing these variables will be opened automatically with the standard editor. After making the necessary settings and saving the file, initialization will continue. 

On future start-ups, the settings file will not be opened automatically. Consequently, the second way aims to make subsequent editions possible, for which the following interface is reserved:

```sh
$ sudo ocariot monitor edit-config
```

#### 3.1.1 Authorization/Authentication Setup

Variables to define the administrator user's credentials the first time the Grafana is instantiated.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `ADMIN_USERNAME` | Username of the default admin user created automatically at the first time the Grafana is instantiated. | `admin` |
| `ADMIN_PASSWORD` | Password of the default admin user created automatically at the first time the Grafana is instantiated. | `admin` |

#### 3.1.2 SMTP Setup

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `GF_SMTP_ENABLED` | Enable SMTP server settings. | `false` |
| `GF_SMTP_HOST` | Host where the SMTP server is allocated. | `smtp.gmail.com:465` |
| `GF_SMTP_USER` | Registered email on the SMTP server. It will be used to send emals when an alarm is detected. | `grafana@test.com` |
| `GF_SMTP_PASSWORD` | Password for the email registered on the SMTP server. | `secret` |

### 3.2 Building and Deploying the containers

#### 3.2.1 Start containers

To execute all the necessary commands to lift the entire stack of containers use the following interface:

```sh
$ sudo ocariot monitor start
```

Lifting all containers may take a few seconds or a few minutes.

#### 3.2.2 Stop containers
To stop the stack, you can run the `stop` interface . This will cause all containers to be stopped. The volumes will remain intact.

```sh
$ sudo ocariot monitor stop
```

*Optional parameters:*

- `--services <values>` - Defines a set of services to be stopped. The delimiter for specifying one more service is space. For example: `sudo ocariot monitor stop --services grafana prometheus`;
- `--clear-volumes` - Argument used to remove all volumes. However, **be careful as the process is irreversible.**

#### 3.2.3 Backup

To perform the backup generation of all volumes used by the OCARIoT platform, the following interface is reserved:

```sh
$ sudo ocariot monitor backup
```

:pushpin: Note: If they are running, the services that will participate in the backup operation will be temporarily stopped. At the end of the backup operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--services <values>` - Defines a set of services from which you want to generate the backup. The delimiter for specifying one more service is space. For example: `sudo ocariot monitor backup --services grafana prometheus`;
- `--expression <values>` - Parameter used to define a crontab expression that will schedule the generation of a backup. The value of this option must be passed in double quotes. Example: `sudo ocariot monitor backup --expression "0 3 * * *"`;
- `--path <values>` - Parameter used to specify the path where the backup will be saved. If this option is omitted, the backup files will be placed at the place of execution of the command currently described.

#### 3.2.4 Restore
In order to restore all backups of the volumes present in the current path, the following interface is reserved:

```sh
$ sudo ocariot monitor restore
```

:pushpin: Note: If they are running, the services that will participate in the restore operation will be temporarily stopped. At the end of the restore operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--path` - Parameter used to specify the path where the backup files will be searched for restoring from a previous backup performed. If this option is omitted, the backup files will be searched at the place of execution of the command currently described;
- `--services <values>` - Defines a set of services that will have their volumes restored. The delimiter for specifying one more service is space. For example: `sudo ocariot monitor restore --services grafana prometheus`;
- `--time` - You can restore from a particular backup by adding a time parameter to the command restore. For example, using restore `--time 3D `at the end in the above command will restore a backup from 3 days ago. See the [Duplicity manual](http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8) to view the accepted time formats.

## 4. Update Software

Command used to update the OCARIoT software interfaces. It will be updated to the latest release.

```sh
$ sudo ocariot update
```

## 5. Uninstall
Interface used to uninstall the OCARIoT platform, this includes removing pre-scheduled backups. Running services will be stopped.

```sh
$ sudo ocariot uninstall
```

*Optional parameters:*

- `--clear-volumes` - Argument used to remove all volumes. However, **be careful as the process is irreversible.**

## 6. Version

Command used to view the current version of the installed OCARIoT software.

```sh
$ sudo ocariot version
```

-----

## Future Features
- Log Manager;
- Multiple replicas for important nodes.


[//]: # (These are reference links used in the body of this note.)
[license-image]: https://img.shields.io/badge/license-Apache%202-blue.svg
[license-url]: https://github.com/ocariot/docker-swarm/blob/master/LICENSE
[last-commit-image]: https://img.shields.io/github/last-commit/ocariot/docker-swarm.svg
[last-commit-url]: https://github.com/ocariot/docker-swarm/commits
[releases-image]: https://img.shields.io/github/release-date/ocariot/docker-swarm.svg
[releases-url]: https://github.com/ocariot/docker-swarm/releases
[contributors-image]: https://img.shields.io/github/contributors/ocariot/docker-swarm.svg
[contributors-url]: https://github.com/ocariot/docker-swarm/graphs/contributors
