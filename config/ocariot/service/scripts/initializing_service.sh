#!/usr/bin/env bash

# Function utilized to read JSON
read_json()
{
   echo $2 | grep -Po "\"$1\":.*?[^\\\]\"" | sed "s/\\\"//g;s/,//g;s/$1://g"
}

# Function to get credentials to mount URI and to access PSMDB
get_psmdb_credential()
{
    PS_NAME="PSMDB"
    if [ "$(echo ${HOSTNAME} | grep missions)" ];then
        PS_NAME="PSMYSQL"
    fi

    RET_CREDENTIAL=1
    while [[ $RET_CREDENTIAL -ne 200 ]]; do
        echo "=> Waiting for ${PS_NAME} credential..."
        # The requests are realized every 2 seconds
        sleep 2
        # Request to get access credential for PSMDB
        RET_CREDENTIAL=$(curl \
                --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
                --cacert /tmp/vault/ca.crt --silent \
                --output /tmp/psmdb_credential.json -w "%{http_code}\n" \
                ${VAULT_BASE_URL}:${VAULT_PORT}/v1/database/creds/${HOSTNAME})
    done

    # Identifying the service that is running the script
    local CONTAINER=$(echo ${HOSTNAME} | sed 's/-service//g')

    # Processing credentials received
    CREDENTIAL=$(cat /tmp/psmdb_credential.json)

    # User received
    local USER=$(read_json username ${CREDENTIAL})
    # Password received
    local PASSWD=$(read_json password ${CREDENTIAL})

    if [ "${PS_NAME}" = "PSMDB" ]; then
        # Mounting environment variable and placing in "~/.bashrc" file
        echo "export MONGODB_URI=mongodb://${USER}:${PASSWD}@psmdb-${CONTAINER}:27017/${CONTAINER}?ssl=true" >> ~/.bashrc
    else
        echo "export DATABASE_USER_NAME=${USER}" >> ~/.bashrc
        echo "export DATABASE_USER_PASSWORD=${PASSWD}" >> ~/.bashrc
    fi

    # Executing "~/.bashrc" script to enable MONGODB_URI environment variable
    source ~/.bashrc

    # Removing temporary file utilized in request
    rm /tmp/psmdb_credential.json
}

# Function to get credentials to mount URI and to access RabbitMQ
get_rabbitmq_credential()
{
    RET_CREDENTIAL=1
    while [[ $RET_CREDENTIAL -ne 200 ]]; do
        echo "=> Waiting for RabbitMQ credential..."
        # The requests are realized every 2 seconds
        sleep 2
        # Request to get access credential for RabbitMQ
        RET_CREDENTIAL=$(curl \
                --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
                --cacert /tmp/vault/ca.crt --silent \
                --output /tmp/rabbitmq_credential.json -w "%{http_code}\n" \
                ${VAULT_BASE_URL}:${VAULT_PORT}/v1/rabbitmq/creds/read_write)
    done

    # Processing credentials received
    CREDENTIAL=$(cat /tmp/rabbitmq_credential.json)

    # User received
    local USER=$(read_json username ${CREDENTIAL})
    # Password received
    local PASSWD=$(read_json password ${CREDENTIAL})

    # Mounting environment variable and placing in "~/.bashrc" file
    echo "export RABBITMQ_URI=amqps://${USER}:${PASSWD}@rabbitmq:5671" >> ~/.bashrc

    # Executing "~/.bashrc" script to enable RABBITMQ_URI environment variable
    source ~/.bashrc

    # Removing temporary file utilized in request
    rm /tmp/rabbitmq_credential.json
}

# Function to get server certificates from Vault
get_certificates()
{
    RET_CERT=1
    while [[ $RET_CERT -ne 200 ]]; do
        echo "=> Waiting for certificates..."
        # The requests are realized every 2 seconds
        sleep 2
        # Request to get server certificates from Vault
        RET_CERT=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --request POST \
            --data-binary "{\"common_name\": \"${HOSTNAME}\"}" \
            --cacert /tmp/vault/ca.crt --silent \
            --output /tmp/certificates.json -w "%{http_code}\n" \
            ${VAULT_BASE_URL}:${VAULT_PORT}/v1/pki/issue/${HOSTNAME})
    done

    # Processing certificates
    CERTIFICATES=$(cat /tmp/certificates.json)

    # Placing and referencing private key server for /etc/.certs/server.key
    # through of SSL_KEY_PATH environment variable
    PRIVATE_KEY=$(read_json private_key "${CERTIFICATES}")
    echo -e "${PRIVATE_KEY}" > /etc/.certs/server.key
    echo "export SSL_KEY_PATH=/etc/.certs/server.key" >> ~/.bashrc

    # Placing and referencing public key server for /etc/.certs/server.cert
    # through of SSL_CERT_PATH environment variable
    CERTIFICATE=$(read_json certificate "${CERTIFICATES}")
    echo -e "${CERTIFICATE}" > /etc/.certs/server.cert
    echo "export SSL_CERT_PATH=/etc/.certs/server.cert" >> ~/.bashrc

    # Placing and referencing ca server for /etc/.certs/ca.crt
    # through of RABBITMQ_CA_PATH environment variable
    CA=$(read_json issuing_ca "${CERTIFICATES}")
    echo -e "${CA}" > /etc/.certs/ca.crt
    echo "export RABBITMQ_CA_PATH=/etc/.certs/ca.crt" >> ~/.bashrc

    # Removing temporary file utilized in request
    rm /tmp/certificates.json
}

# General function to monitor the receiving of access token from Vault
configure_environment()
{
    # Creating folder where all certificates will be placed
    mkdir -p /etc/.certs

    # Waiting the access token to be generate.
    # Obs: Every access token file are mapped based in its respective hostname
    RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} |awk '{print $3}')
    while [[ ${RET} == "" ]]; do
        echo "=> Waiting for Token of ${HOSTNAME} service..."
        # Monitoring the token file every 5 seconds
        sleep 5
        RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} | awk '{print $3}')
    done

    # Establishing access token received as environment variable
    source /tmp/access-token-${HOSTNAME}
    # Clearing access token file
    > /tmp/access-token-${HOSTNAME}
}

# Function to get JWT and encrypt secret key from Vault
# This function is used by account service only.
get_jwt_encrypt_keys()
{
    # checking the service that is executing the script
    if [ ${HOSTNAME} = "account-service" ]; then
        local JWT_RET=1
        local ENCRYPT_SECRET_KEY_RET=1
        while [[ $JWT_RET -ne 200 ]] || [[ $ENCRYPT_SECRET_KEY_RET -ne 200 ]]; do
            echo "=> Waiting for JWT_KEYS and ENCRYPT_SECRET_KEY for account-service..."
            # The requests are realized every 2 seconds
            sleep 2
            # Request to get JWT keys from Vault
            JWT_RET=$(curl \
                    --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
                    --cacert /tmp/vault/ca.crt --silent \
                    --output /tmp/jwt_keys.json -w "%{http_code}\n" \
                    ${VAULT_BASE_URL}:${VAULT_PORT}/v1/secret/data/${HOSTNAME}/jwt)

            # Request to get encrypt secret key from Vault
            ENCRYPT_SECRET_KEY_RET=$(curl \
                    --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
                    --cacert /tmp/vault/ca.crt --silent \
                    --output /tmp/encrypt_secret_key.json -w "%{http_code}\n" \
                    ${VAULT_BASE_URL}:${VAULT_PORT}/v1/secret/data/${HOSTNAME}/encrypt-secret-key)
        done

        # Processing JWT keys and encrypt secret key
        JWT_KEYS=$(cat /tmp/jwt_keys.json)
        ENCRYPT_SECRET_KEY=$(cat /tmp/encrypt_secret_key.json)

        # Placing and referencing private key for /etc/.certs/jwt.key
        # through of JWT_PRIVATE_KEY_PATH environment variable
        PRIVATE_KEY=$(read_json private_key "${JWT_KEYS}")
        echo -e "${PRIVATE_KEY}" > /etc/.certs/jwt.key
        echo "export JWT_PRIVATE_KEY_PATH=/etc/.certs/jwt.key" >> ~/.bashrc

        # Placing and referencing private key for /etc/.certs/jwt.pub
        # through of JWT_PUBLIC_KEY_PATH environment variable
        PUBLIC_KEY=$(read_json public_key "${JWT_KEYS}")
        echo -e "${PUBLIC_KEY}" > /etc/.certs/jwt.pub
        echo "export JWT_PUBLIC_KEY_PATH=/etc/.certs/jwt.pub" >> ~/.bashrc

        # Referencing ENCRYPT_SECRET_KEY environment variable
        ENCRYPT_SECRET_KEY=$(read_json value "${ENCRYPT_SECRET_KEY}")
        echo "export ENCRYPT_SECRET_KEY=${ENCRYPT_SECRET_KEY}" >> ~/.bashrc

        # Removing temporary files utilized in requests
        rm /tmp/jwt_keys.json
        rm /tmp/encrypt_secret_key.json
    fi
}

# General function to monitor the receiving of access token from Vault
configure_environment

# Function to get server certificates from Vault
get_certificates

# Function to get JWT and encrypt secret key from Vault
# This function is used by account service only.
get_jwt_encrypt_keys

# Function to get credentials to mount URI and to access PSMDB
get_psmdb_credential

# Function to get credentials to mount URI and to access RabbitMQ
get_rabbitmq_credential

# Removing the environment variable access token
unset VAULT_ACCESS_TOKEN

# Starting service
npm start
