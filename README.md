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


## 1. Set the environment variables
To ensure flexibility and increase the security of the platform, the OCARIoT services receive some parameters through environment variables, e.g. IPs, credentials (username and password), etc.

The file `.env.example` contains all the environment variables required by the services being deployed.

Copy and paste with the file `.env.example` with the name `.env` to make the Docker Swarm use the environment variables defined in this file:

```sh
$ cp .env.example .env
```

### 1.1 External Service URL
Variables to define the URL of services to be exposed, such as Vault and RabbitMQ Management. This is useful for viewing data saved in Vault and managing the Message Bus.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `VAULT_BASE_URL` |  Vault service URL. Used by internal services in requests to Vault.  It is not necessary to define a port, it is defined in another variable. | `https://api.ocariot.com.br` |
| `RABBITMQ_MGT_BASE_URL` | RabbitMQ Management URL. Used by internal services in requests to RabbitMQ.  It is not necessary to define a port, it is defined in another variable. | `https://api.ocariot.com.br` |


### 1.2 External Service Ports
Variables to define the ports of services to be exposed, such as API Gateway, Vault, and RabbitMQ Management.

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `AG_PORT_HTTP` |  Port used by the API Gateway service to listen for HTTP request. Automatically redirects to HTTPS port. | `80` |
| `AG_PORT_HTTPS` | Port used by the API Gateway service to listen for HTTPS request. | `443` |
| `VAULT_PORT` | Port used by the Vault service to listen for HTTPS request. | `8200` |
| `RABBITMQ_MGT_PORT` | Port used by RabbitMQ Management to service the HTTPS request. | `15671` |


### 1.3 Certificates/keys
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


### 1.4 Data Sync Setup
Variables used by the Data Sync Agent microservice, responsible for data synchronization between Fitbit and OCARIoT platforms. This information is provided by Fitbit when registering an OAuth2 client. Please, **contact the partner responsible for microservice development to obtain the values for each variable.**

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `FITBIT_CLIENT_ID` | Client Id for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `11ABWZ` |
| `FITBIT_CLIENT_SECRET` |  Client Secret for Fitbit Application resposible to manage user data. This information is later shared through the REST API to the android application _(DA App)_. | `1234ab56cd789123wzd123a` |
| `FITBIT_SUB_VERIFY_CODE` | Code used by Fitbit to verify the subscriber. |  `440be54d7202be1126b94d0`  |
| `FITBIT_SUB_ID` | Customer Subscriber ID, used to manage the subscriber who will receive notification of a user resource. | `BR1AbxwzbzP8` |
| `EXPRESSION_AUTO_SYNC` | Frequency time that the application will sync the users data in background according to the crontab expression. For example, the value `0 * * * *` means that synchronization will occur every hour. | `"0 * * * *"` |


## 2. Building and Deploying the containers

After making all the necessary settings in the `.env` file, simply run the `start.sh` script with a name for the stack, for example `ocariot`. It will execute all commands necessary to lift the entire stack of containers.

```sh
$ ./start.sh ocariot
```

Lifting all containers may take a few seconds or a few minutes. When the entire stack has been successfully initialized, you will see the following message on the terminal: `Stack initialized successfully!!! :)` followed by the OCARIoT logo.

## 3. Stop containers
To stop the stack, you can run the `stop.sh` script by providing the name of the stack you used at start [(2)](#2-Building-and-Deploying-the-containers). This will cause all containers to be stopped. The volumes will remain intact.

```sh
$ ./stop.sh ocariot
```

Optionally, you can pass the `-clear-volumes` argument to remove all volumes. However, **be careful as the process is irreversible.**

```sh
$ ./stop.sh ocariot -clear-volumes
```


-----

## Future Features
- Automated Backups;
- Dashboard for container manager;
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
