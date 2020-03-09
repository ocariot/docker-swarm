#!/usr/bin/env bash

# Function utilized to read JSON
read_json()
{
   echo $2 | grep -Po "\"$1\":.*?[^\\\]\"" | sed "s/\\\"//g;s/,//g;s/$1://g"
}

# Checking if mongodb was initialized
check_psmysql()
{
    # Waiting for PSMYSQL to boot
    while [[ $(netstat -t -l -p --numeric-ports | grep -wc 3306) -eq 0 ]]; do
        echo "=> Waiting for confirmation of MySQL service startup..."
        # The attempts are realized in each 5 seconds
        sleep 5
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

    mkdir -p /etc/mysql-ssl/

    # Processing certificates
    CERTIFICATES=$(cat /tmp/certificates.json)

    PRIVATE_KEY=$(read_json private_key "${CERTIFICATES}")
    echo -e "${PRIVATE_KEY}" > /etc/mysql-ssl/server-key.pem

    CERTIFICATE=$(read_json certificate "${CERTIFICATES}")
    echo -e "${CERTIFICATE}" > /etc/mysql-ssl/server-cert.pem

    CA=$(read_json issuing_ca "${CERTIFICATES}")
    echo -e "${CA}" > /etc/mysql-ssl/ca.pem

    chmod -R 0555 /etc/mysql-ssl/

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
            ${VAULT_BASE_URL}/v1/secret-v1/${HOSTNAME}/credential)
done

# Processing credentials received
CREDENTIAL=$(cat /tmp/admin_credential.json)

# Username admin
USER=$(read_json user "${CREDENTIAL}")
# Password admin
PASSWD=$(read_json passwd "${CREDENTIAL}")

# Removing temporarily file utilized in request
rm /tmp/admin_credential.json

# Checking if mongodb was initialized
check_psmysql

# Establish connection with mongo and creating user admin
mysql <<EOF
create database $(echo ${HOSTNAME} | sed 's/psmysql-//g');
DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'mysql.infoschema', 'mysql.session');
CREATE USER "${USER}"@"%" IDENTIFIED BY "${PASSWD}";
GRANT ALL ON *.* TO "${USER}"@"%" WITH GRANT OPTION ;
flush privileges;
EOF

# Function to realize token Revocation
revoke_token

echo "Finalizing user creating"
}

# General function to monitor the receiving of access token from
# Vault and to modify "mongod.conf" file based in service hostname
configure_environment()
{
    # Creating folders used to save  the configuration files
    mkdir -p /tmp/vault/

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

VAULT_PORT=$(echo ${VAULT_BASE_URL} | grep -oE "[^:]+$")
VAULT_URL=$(echo ${VAULT_BASE_URL} | sed "s/:${VAULT_PORT}// g")

cat > "/etc/keyring_vault.conf" << EOF
vault_url = ${VAULT_URL}:${VAULT_PORT}
secret_mount_point = secret-v1/psmysql-missions/encryptionKey
token = ${VAULT_ACCESS_TOKEN}
vault_ca = /tmp/vault/ca.crt
EOF
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

## Function to get server certificates from Vault
get_certificates
#
## Function to create admin user and to revoke Vault token after
## finalized configurations
add_user &

## Starting MongoDB
/docker-entrypoint.sh mysqld