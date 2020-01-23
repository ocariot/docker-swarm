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
                    --cacert /tmp/vault/ca.crt  --silent \
                    --output /tmp/jwt_public_key.json -w "%{http_code}\n" \
                    ${VAULT_BASE_URL}:${VAULT_PORT}/v1/secret/data/${HOSTNAME}/jwt)
        echo ${RET}
    done

    # Placing and referencing JWT public key for /etc/.certs/jwt.pub
    # through of JWT_PUBLIC_KEY_PATH environment variable
    KEYS=$(cat /tmp/jwt_public_key.json)
    PUBLIC_KEY=$(read_json public_key "${KEYS}")
    echo -e "${PUBLIC_KEY}" > /etc/.certs/jwt.pub
    echo "export JWT_PUBLIC_KEY_PATH=/etc/.certs/jwt.pub" >> ~/.bashrc

    # Executing "~/.bashrc" script to enable JWT_PUBLIC_KEY_PATH environment variable
    source ~/.bashrc

    # Removing temporarily file utilized in request
    rm  /tmp/jwt_public_key.json
}

# General function to monitor the receiving of access token from Vault
configure_environment()
{
    # Waiting the access token to be generate.
    # Obs: Every access token file are mapped based in its respective hostname
    RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} | awk '{print $3}')
    while [[ ${RET} == "" ]]; do
        echo "=> Waiting for Token of ${HOSTNAME} service..."
        sleep 5
        RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} | awk '{print $3}')
    done

    # Establishing access token received as environment variable
    source /tmp/access-token-${HOSTNAME}
    # Clearing access token file
    > /tmp/access-token-${HOSTNAME}
}

# General function to monitoring the receiving of access token from Vault
configure_environment

# Function utilized to get the JWT public key from Vault
get_public_jwt

# Removing the environment variable access token
unset VAULT_ACCESS_TOKEN

# Starting API Gateway
npm start
