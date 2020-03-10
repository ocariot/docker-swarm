#!/usr/bin/env bash

# Checking if mongodb was initialized
check_mongo()
{
    # Waiting for MongoDB to boot
    RET=1
    while [[ RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of MongoDB service startup..."
        # The attempts are realized in each 5 seconds
        sleep 5
        mongo admin --port 27017 --sslAllowInvalidCertificates --ssl --eval "help" >/dev/null 2>&1
        RET=$?
    done
}

# Function to get server certificates from Vault
get_certificates()
{
    RET_CERT_MONGO=1
    while [[ $RET_CERT_MONGO -ne 200 ]]; do
        echo "=> Waiting for certificates..."
        # The requests are realized in each 2 seconds
        sleep 2
        # Request to get server certificates from Vault
        RET_CERT_MONGO=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --request POST \
            --data-binary "{\"common_name\": \"${HOSTNAME}\"}" \
            --cacert /tmp/vault/ca.crt --silent \
            --output /tmp/certificates.json -w "%{http_code}\n" \
            ${VAULT_BASE_URL}/v1/pki/issue/${HOSTNAME})
    done

    # Processing and placing private key server for /tmp/mongodb/ssl/mongodb.pem file
    CERTIFICATES=$(jq '.data.private_key, .data.certificate' /tmp/certificates.json)
    printf "${CERTIFICATES}" | sed 's/\"//g' > /tmp/mongodb/ssl/mongodb.pem

    # Processing and placing public key server for /tmp/mongodb/ssl/caToValidateClientCertificates.pem
    CA_CERTIFICATE=$(jq '.data.issuing_ca' /tmp/certificates.json)
    printf "${CA_CERTIFICATE}" | sed 's/\"//g' > /tmp/mongodb/ssl/caToValidateClientCertificates.pem

    # Removing temporarily file utilized in request
    rm /tmp/certificates.json
}

# Function to create admin user and to revoke Vault token after
# finalized configurations
add_user()
{
echo "Initializing user creating"

RET_CREDENTIAL=1
while [[ $RET_CREDENTIAL -ne 200 ]]; do
    echo "=> Waiting for Admin Credentials..."
    sleep 2
    # Requesting admin user credentials to create user in PSMDB
    RET_CREDENTIAL=$(curl \
            --header "X-Vault-Token: ${VAULT_ACCESS_TOKEN}" \
            --cacert /tmp/vault/ca.crt --silent \
            --output /tmp/admin_credential.json -w "%{http_code}\n" \
            ${VAULT_BASE_URL}/v1/secret/data/${HOSTNAME}/credential)
done

# Processing credentials received
CREDENTIAL=$(cat /tmp/admin_credential.json | jq '.data.data.user, .data.data.passwd')

# Username admin
USER=$(echo $CREDENTIAL | awk 'NR == 1{print $1}')
# Password admin
PASSWD=$(echo $CREDENTIAL | awk 'NR == 1{print $2}')

# Removing temporarily file utilized in request
rm /tmp/admin_credential.json

# Checking if mongodb was initialized
check_mongo

# Establish connection with mongo and creating user admin
mongo  --port 27017 --sslAllowInvalidCertificates --ssl <<EOF
use admin;
db.createUser(
  {
    user: ${USER},
    pwd: ${PASSWD},
    roles: ["userAdminAnyDatabase", "dbAdminAnyDatabase", "readWriteAnyDatabase"]
  });
EOF

# Function to realize token Revocation
revoke_token

echo "Finalizing user creating"
}

# General function to monitor the receiving of access token from
# Vault and to modify "mongod.conf" file based in service hostname
configure_environment()
{
    # Processing "mongod.conf" file based in service hostname
    VAULT_PORT=$(echo ${VAULT_BASE_URL} | grep -oE "[^:]+$")
    VAULT_URL=$(echo ${VAULT_BASE_URL} | sed "s/\(:\|\/\)/ /g" | awk '{print $2}')
    sed s/__DOMAIN__/$(echo ${VAULT_URL} | grep -oE '[^/]*$')/g /tmp/base_conf_mongod > /tmp/mongod.conf
    sed -i s/__PORT__/${VAULT_PORT}/g /tmp/mongod.conf
    sed -i s/__PATH__/${HOSTNAME}/g /tmp/mongod.conf

    # Creating folders used to save  the configuration files
    mkdir -p /tmp/vault/
    mkdir -p /tmp/mongodb/ssl/

    # Waiting the access token to be generate.
    # Obs: Every access token file are mapped based in its respective hostname
    RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} |awk '{print $3}')
    while [[ ${RET} == "" ]]; do
        echo "=> Waiting for Token of ${HOSTNAME} service..."
        sleep 5
        RET=$(sed 's/=/ /g' /tmp/access-token-${HOSTNAME} |awk '{print $3}')
    done

    # Establishing access token received as environment variable
    source /tmp/access-token-${HOSTNAME}
    # Clearing access token file
    > /tmp/access-token-${HOSTNAME}

    # Placing the access token in its file defined in PSMDB
    # settings to execute the encryption key request to the Vault
    echo ${VAULT_ACCESS_TOKEN} > /tmp/psmdb-tokenFile
    # Setting the permission of the file containing the token
    chmod 0440 /tmp/psmdb-tokenFile
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
            --cacert /tmp/vault/ca.crt --silent \
            ${VAULT_BASE_URL}/v1/auth/token/revoke-self -w "%{http_code}\n")
    done

    # Removing the environment variable access token
    unset VAULT_ACCESS_TOKEN
}

# General function to monitor the receiving of access token from
# Vault and to modify "mongod.conf" file based in service hostname
configure_environment

# Function to get server certificates from Vault
get_certificates

# Function to create admin user and to revoke Vault token after
# finalized configurations
add_user &

# Starting MongoDB
mongod --config /tmp/mongod.conf --logpath /proc/1/fd/1 --logappend --verbose
