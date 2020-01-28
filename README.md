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

## 1. Instalation
All software installation is performed using the following command:

```sh
curl -o- https://raw.githubusercontent.com/ocariot/docker-swarm/1.2.0/install.sh | sudo bash
```

```sh
wget -qO- https://raw.githubusercontent.com/ocariot/docker-swarm/1.2.0/install.sh | sudo bash
```



After the execution of this script has finished, the message `****OCARIoT Project was installed with success!****` will be displayed, thus demonstrating that the software installation was successful. Otherwise, the message to be displayed will be `OCARIoT Project wasn't installed with success!`.

If script execution is successful, the ocariot command will be recognized by bash:

![](https://i.imgur.com/X3BURZP.png)

:pushpin: Note: The directory adopted for installing the software is a location that requires sudo privileges, therefore, for the execution of the ocariot command, the sudo prefix will always be necessary. For example: `sudo ocariot stack start`. 


## 2. Set the environment variables
To ensure flexibility and increase the security of the platform, the OCARIoT services receive some parameters through environment variables, e.g. IPs, credentials (username and password), etc.

There are two ways to edit these environment variables. The first is during the first startup (`sudo ocariot stack start`), where the file containing these variables will be opened automatically with the standard editor. After making the necessary settings and saving the file, initialization will continue. 

On future start-ups, the settings file will not be opened automatically. Consequently, the second way aims to make subsequent editions possible, for which the following interface is reserved:

```sh
$ sudo ocariot stack edit-config
```

### 2.1 External Service URL
Variables to define the URL of services to be exposed, such as Vault and RabbitMQ Management. This is useful for viewing data saved in Vault and managing the Message Bus.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `VAULT_BASE_URL` |  Vault service URL. Used by internal services in requests to Vault.  It is not necessary to define a port, it is defined in another variable. | `https://api.ocariot.com.br` |
| `RABBITMQ_MGT_BASE_URL` | RabbitMQ Management URL. Used by internal services in requests to RabbitMQ.  It is not necessary to define a port, it is defined in another variable. | `https://api.ocariot.com.br` |


### 2.2 External Service Ports
Variables to define the ports of services to be exposed, such as API Gateway, Vault, and RabbitMQ Management.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `AG_PORT_HTTP` |  Port used by the API Gateway service to listen for HTTP request. Automatically redirects to HTTPS port. | `80` |
| `AG_PORT_HTTPS` | Port used by the API Gateway service to listen for HTTPS request. | `443` |
| `VAULT_PORT` | Port used by the Vault service to listen for HTTPS request. | `8200` |
| `RABBITMQ_MGT_PORT` | Port used by RabbitMQ Management to service the HTTPS request. | `15671` |


### 3.3 Certificates/keys
Variables to define the ports of services to be exposed, such as API Gateway, Vault, and RabbitMQ Management.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `AG_KEY_PATH` | API Gateway private key. | `mycerts/privkey.pem` |
| `AG_CERT_PATH` | API Gateway domain certificate/public key. | `mycerts/fullchain.pem` |
| `VAULT_KEY_PATH` | Vault private key. | `mycerts/privkey.pem` |
| `VAULT_CERT_PATH` | Vault domain certificate/public key. | `mycerts/cert.pem` |
| `VAULT_CA_CERT_PATH` | Vault CA certificate. | `mycerts/chain.pem` |
| `RABBITMQ_MGMT_KEY_PATH` | RabbitMQ Management private key. | `mycerts/privkey.pem` |
| `RABBITMQ_MGT_CERT_PATH` | RabbitMQ Management domain certificate/public key. | `mycerts/cert.pem` |
| `RABBITMQ_MGT_CA_CERT_PATH` | RabbitMQ Management CA certificate. | `mycerts/chain.pem` |


### 4.4 Data Sync Setup
Variables used by the Data Sync Agent microservice, responsible for data synchronization between Fitbit and OCARIoT platforms. This information is provided by Fitbit when registering an OAuth2 client. Please, **contact the partner responsible for microservice development to obtain the values for each variable.**

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `FITBIT_CLIENT_ID` | Client Id for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `11ABWZ` |
| `FITBIT_CLIENT_SECRET` |  Client Secret for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `1234ab56cd789123wzd123a` |
| `FITBIT_SUB_VERIFY_CODE` | Code used by Fitbit to verify the subscriber. |  `440be54d7202be1126b94d0`  |
| `FITBIT_SUB_ID` | Customer Subscriber ID, used to manage the subscriber who will receive notification of a user resource. | `BR1AbxwzbzP8` |
| `EXPRESSION_AUTO_SYNC` | Frequency time that the application will sync the users data in background according to the crontab expression. For example, the value `0 * * * *` means that synchronization will occur every hour. | `"0 * * * *"` |


## 3. Building and Deploying the containers

To execute all the necessary commands to lift the entire stack of containers use the following interface:

```sh
$ sudo ocariot stack start
```

Lifting all containers may take a few seconds or a few minutes. When the entire stack has been successfully initialized, you will see the following message on the terminal: `Stack initialized successfully!!! :)` followed by the OCARIoT logo.

> :warning: **During the first boot, the encryption keys and root access token will be generated. This content will be made available in the *keys* file, which will be generated at the place of execution of the command currently described. This file is of fundamental importance for the restoration of backups.**
>
>:warning: **It is also noteworthy that these keys must be kept in an offline environment, considering that the leakage of such keys will result in an environment of high vulnerability.**

## 4. Stop containers
To stop the stack, you can run the `stop` interface . This will cause all containers to be stopped. The volumes will remain intact.

```sh
$ sudo ocariot stack stop
```

*Optional parameters:*

- `--services <values>` - Defines a set of services to be stopped. The delimiter for specifying one more service is space. For example: `sudo ocariot stack stop --services account iot-tracking`;
- `--clear-volumes` - Argument used to remove all volumes. However, **be careful as the process is irreversible.**

## 4. Backup

To perform the backup generation of all volumes used by the OCARIoT platform, the following interface is reserved:

```sh
$ sudo ocariot stack backup
```

:pushpin: Note: If they are running, the services that will participate in the backup operation will be temporarily stopped. At the end of the backup operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--services <values>` - Defines a set of services from which you want to generate the backup. The delimiter for specifying one more service is space. For example: `sudo ocariot stack backup --services account iot-tracking`;
- `--expression <values>` - Parameter used to define a crontab expression that will schedule the generation of a backup. The value of this option must be passed in double quotes. Example: `sudo ocariot stack backup --expression "0 3 * * *"`;
- `--path <values>` - Parameter used to specify the path where the backup will be saved. If this option is omitted, the backup files will be placed at the place of execution of the command currently described.

## 5. Restore
In order to restore all backups of the volumes present in the current path, the following interface is reserved:

```sh
$ sudo ocariot stack restore
```

:pushpin: Note: If they are running, the services that will participate in the restore operation will be temporarily stopped. At the end of the restore operation, all services that were active will be restarted automatically.

*Optional parameters:*

- `--keys` - Specifies the location of the file containing the encryption keys and root tokenused by the vault. TThis file was generated at the first start of the OCARIoT stack using the command [`sudo ocariot stack start`](#3-Building-and-Deploying-the-containers);
- `--path` - Parameter used to specify the path where the backup files will be searched for restoring from a previous backup performed. If this option is omitted, the backup files will be searched at the place of execution of the command currently described;
- `--services <values>` - Defines a set of services that will have their volumes restored. The delimiter for specifying one more service is space. For example: `sudo ocariot stack restore --services account iot-tracking`;
- `--time` - You can restore from a particular backup by adding a time parameter to the command restore. For example, using restore `--time 3D `at the end in the above command will restore a backup from 3 days ago. See the [Duplicity manual](http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8) to view the accepted time formats .

## 5. Plataform Images Update

Interface used to update the docker images used by the OCARIoT microservices.

```sh
$ sudo ocariot stack update-images
```
*Optional parameters:*

- `--services <values>` - Defines a set of images of the services to be updated. The delimiter for specifying one more service is space. For example: `sudo ocariot stack update-images --services account iot-tracking`.

## 6. Update Software

Command used to update the OCARIoT software interfaces. It will be updated to the latest release.

```sh
$ sudo ocariot update
```

## 7. Uninstall
Interface used to uninstall the OCARIoT platform, this includes removing pre-scheduled backups. Running services will be stopped.

```sh
$ sudo ocariot uninstall
```

*Optional parameters:*

- `--clear-volumes` - Argument used to remove all volumes. However, **be careful as the process is irreversible.**

-----

## Future Features
- Integration of the MySQL database for the missions service;
- Dashboard to monitor container health;
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
