#!/usr/bin/env bash

# Function utilized to read JSON
read_json()
{
   echo $2 | grep -Po "\"$1\":.*?[^\\\]\"" | sed "s/\\\"//g;s/,//g;s/$1://g"
}

# Function utilized to get the JWT public key from Vault
get_public_jwt()
{
    # API Gateway service requesting JWT public key to Vault and save
    # temporarily in /tmp/jwt_public_key.json
    local RET=1
    while [[ $RET -ne 200 ]]; do
        echo "=> Waiting for JWT_KEYS for api-gateway-service..."
        sleep 2
        RET=$(curl \
                    --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
                    --silent \
                    --output /tmp/jwt_public_key.json -w "%{http_code}\n" \
                    ${VAULT_SERVICE}/v1/secret/data/${HOSTNAME}/jwt)
        echo ${RET}
    done

    # Placing and referencing JWT public key for /etc/.certs/jwt.pub
    # through of JWT_PUBLIC_KEY_PATH environment variable
    KEYS=$(cat /tmp/jwt_public_key.json)
    PUBLIC_KEY=$(read_json public_key "${KEYS}")
    echo -e "${PUBLIC_KEY}" > /etc/.certs/jwt.pub
    echo "export JWT_PUBLIC_KEY_PATH=/etc/.certs/jwt.pub" >> ~/.bashrc

    # Removing temporarily file utilized in request
    rm  /tmp/jwt_public_key.json
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
            --data-binary "{\"common_name\": \"${API_IOT_HOSTNAME}\"}" \
            --silent \
            --output /tmp/certificates.json -w "%{http_code}\n" \
            ${VAULT_SERVICE}/v1/pki/issue/${HOSTNAME})
    done

    mkdir -p /etc/.certs/iot_device

    # Processing certificates
    CERTIFICATES=$(cat /tmp/certificates.json)

    # Placing and referencing private key server for /etc/.certs/iot_device/server.key
    # through of SSL_KEY_PATH environment variable
    PRIVATE_KEY=$(read_json private_key "${CERTIFICATES}")
    echo -e "${PRIVATE_KEY}" > /etc/.certs/iot_device/server.key
    echo "export SSL_IOT_KEY_PATH=/etc/.certs/iot_device/server.key" >> ~/.bashrc

    # Placing and referencing public key server for /etc/.certs/iot_device/server.cert
    # through of SSL_CERT_PATH environment variable
    CERTIFICATE=$(read_json certificate "${CERTIFICATES}")
    echo -e "${CERTIFICATE}" > /etc/.certs/iot_device/server.cert
    echo "export SSL_IOT_CERT_PATH=/etc/.certs/iot_device/server.cert" >> ~/.bashrc

    # Placing and referencing ca server for /etc/.certs/iot_device/ca.crt
    # through of RABBITMQ_CA_PATH environment variable
    CA=$(read_json issuing_ca "${CERTIFICATES}")
    echo -e "${CA}" > /etc/.certs/iot_device/ca.crt
    echo "export SSL_IOT_CA_PATH=/etc/.certs/iot_device/ca.crt" >> ~/.bashrc

    # Removing temporary file utilized in request
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
    RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} | awk '{print $3}')
    while [[ ${RET} == "" ]]; do
        echo "=> Waiting for Token of ${HOSTNAME} service..."
        sleep 5
        RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} | awk '{print $3}')
    done

    # Establishing access token received as environment variable
    set -a && source /tmp/access-token-${HOSTNAME} && set +a
    # Clearing access token file
    > /tmp/access-token-${HOSTNAME}
}

# General function to monitoring the receiving of access token from Vault
configure_environment

# Function utilized to get the JWT public key from Vault
get_public_jwt

# Function to get server certificates from Vault
get_certificates

# Executing "~/.bashrc" script to enable JWT_PUBLIC_KEY_PATH environment variable
source ~/.bashrc

# Starting API Gateway
npm start
