#!/bin/bash

# Function to create admin user and to revoke Vault token after
# finalized configurations
add_user()
{
    RET_CREDENTIAL=1
    while [[ $RET_CREDENTIAL -ne 200 ]]; do
        echo "=> Waiting for Admin Credentials..."
        sleep 2
        # Requesting admin user credentials to create user in RabbitMq
        RET_CREDENTIAL=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --silent \
            --output /tmp/admin_credential.json -w "%{http_code}\n" \
            ${VAULT_BASE_URL}/v1/secret/data/rabbitmq/credential)
    done

    CREDENTIAL=$(cat /tmp/admin_credential.json | jq '.data.data.user, .data.data.passwd')

    # Username admin
    USER=$(echo $CREDENTIAL | awk 'NR == 1{print $1}' | sed 's/"//g')
    # Password admin
    PASSWORD=$(echo $CREDENTIAL | awk 'NR == 1{print $2}' | sed 's/"//g')

    # Waiting for RabbitMQ to boot
    # code 69 refers to service unavailability
    RET=69
    while [ $RET -ne 0 ]
    do
        echo "=> Waiting for confirmation of RabbitMQ service startup..."
        rabbitmqctl await_startup --timeout 20
        RET=$?
    done

    # Creating user admin
    rabbitmqctl add_user $USER $PASSWORD
    # Defining user as Administrator
    rabbitmqctl set_user_tags $USER administrator
    # Creating vhost ocariot
    rabbitmqctl add_vhost ocariot
    # Defining user with all capacities to manager vhost /
    rabbitmqctl set_permissions -p / $USER ".*" ".*" ".*"
    # Defining user with all capacities to manager vhost ocariot
    rabbitmqctl set_permissions -p ocariot $USER ".*" ".*" ".*"
    # Removing guest user
    rabbitmqctl delete_user guest

    rm /tmp/admin_credential.json

    # Function to realize token Revocation
    revoke_token
}

# Function to get server certificates from Vault
get_certificates()
{
    RET_CERT_RABBITMQ=1
    while [[ $RET_CERT_RABBITMQ -ne 200 ]]; do
        echo $2
        # The requests are realized in each 2 seconds
        sleep 2
        # Request to get server certificates from Vault
        RET_CERT_RABBITMQ=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --request POST \
            --data-binary "{\"common_name\": \"rabbitmq\"}" \
            --silent \
            --output /tmp/certificates.json -w "%{http_code}\n" \
            ${VAULT_BASE_URL}/v1/pki/issue/rabbitmq)

    done

    mkdir -p $1

    # Processing and placing CA certificate for /etc/.certs/ca.crt
    echo -e $(jq '.data.issuing_ca' /tmp/certificates.json | sed 's/"//g') > $1/ca.crt

    # Processing and placing private key server for /etc/.certs/server.cert
    echo -e $(jq '.data.certificate' /tmp/certificates.json | sed 's/"//g') > $1/server.cert

    # Processing and placing public key server for /etc/.certs/server.key
    echo -e $(jq '.data.private_key' /tmp/certificates.json | sed 's/"//g') > $1/server.key

    # Removing temporarily file utilized in request
    rm /tmp/certificates.json
}

# Function used to add the Vault CA certificate to the system, with
# this CA certificate Vault becomes trusted.
# Obs: This is necessary to execute requests to the vault.
add_ca_vault()
{
    mkdir -p /usr/share/ca-certificates/extra
    cat /tmp/vault/ca.crt >> /usr/share/ca-certificates/extra/ca_vault.crt
    echo "extra/ca_vault.crt" >> /etc/ca-certificates.conf
    update-ca-certificates
}

# General function to monitor the receiving of access token from Vault
configure_environment()
{
    # Function used to add the Vault CA certificate to the system, with
    # this CA certificate Vault becomes trusted.
    # Obs: This is necessary to execute requests to the vault.
    add_ca_vault &> /dev/null

    # Waiting the access token to be generate.
    # Obs: Every access token file are mapped based in its respective hostname
    RET=$(sed 's/=/ /g' /tmp/access-token-rabbitmq | awk '{print $3}')
    while [[ ${RET} == "" ]]; do
        echo "=> Waiting for Token of rabbitmq service..."
        # Monitoring the token file every 5 seconds
        sleep 5
        RET=$(sed 's/=/ /g' /tmp/access-token-rabbitmq | awk '{print $3}')
    done

    # Establishing access token received as environment variable
    source /tmp/access-token-rabbitmq
    # Clearing access token file
    > /tmp/access-token-rabbitmq
}

# Function to realize token Revocation
revoke_token()
{
    # Routine for requesting token revocation from Vault
    RET=1
    while [[ $RET -ne 204 ]]; do
        echo "=> Revoking Token..."
        RET=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --request POST \
            --silent \
            ${VAULT_BASE_URL}/v1/auth/token/revoke-self -w "%{http_code}\n")
    done

    # Removing the environment variable access token
    unset VAULT_ACCESS_TOKEN
}

# General function to monitor the receiving of access token from Vault
configure_environment

# Function to get server certificates of Bus from Vault
get_certificates "/etc/.certs/bus" "=> Waiting for Bus certificates..."

# Function to get server certificates of Manager from Vault
get_certificates "/etc/.certs/management" "=> Waiting for Manager certificates..."

# Function to create admin user and to revoke Vault token after
# finalized configurations
add_user &

# Starting RabbitMQ
rabbitmq-server
