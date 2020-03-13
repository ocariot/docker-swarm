#!/bin/sh

DEFAULT_MAX_TTL="43800h"
TTL_CERT="35040h"
TTL_RABBITMQ_USER="87600h"
TTL_PSMDB_USER="87600h"
TTL_PSMDB_TOKEN="10m"
TTL_SERVICE_TOKEN="87600h"

# Function to unseal vault
unseal()
{
    # Using the first three keys to unlock the vault
    KEYS=$(cat /etc/vault/.keys)
    ID_KEY=$(( ( RANDOM % 5 )  + 1 ))
    USED_KEYS=0
    while [[ ${USED_KEYS} != 3 ]]
    do
        KEY=$(echo "${KEYS}" | awk NR==${ID_KEY}'{print $4}')

        vault operator unseal "${KEY}" &> /dev/null

        if [ $? != 0 ];then
            echo "Invalid key to unseal vault. Key: ${KEY}"
            exit
        fi

        KEYS=$(echo "${KEYS}" | sed "${ID_KEY}d")
        USED_KEYS=$(( ${USED_KEYS} + 1))
        ID_KEY=$(( ( RANDOM % (5 - USED_KEYS) )  + 1 ))
    done

    echo "Vault unseal with success!"
}

# Authenticating user with root access token
root_user_authentication()
{
    TOKEN=$(awk 'NR == 6{print $4}' /etc/vault/.keys)

    vault login ${TOKEN} &> /dev/null
    if [ $? != 0 ];then
        echo "Invalid root token. Token: ${TOKEN}"
        exit
    fi

    echo "Root user authenticate with success!"
}

# Function to check if vault was initialized
check_vault()
{
    # Waiting for Vault to boot
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of Vault service startup"
        sleep 2
        $(nc -vz ${HOSTNAME} 8200) 2> /dev/null
        RET=$?
    done
}

# Function to check if HA Mode was initialized
check_ha_mode()
{
    # Waiting for HA Mode is active in Vault
    local HA_MODE="standby"
    while [[ $HA_MODE != "active" ]]; do
        echo "=> Waiting Vault confirm the HA Mode Consul service startup"
        sleep 2
        HA_MODE=$(vault status | grep "HA Mode" | awk '{print $3}')
    done
}

# Function to check if Consul was initialized
check_consul()
{
    # Waiting for Consul to boot
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of Consul service startup"
        $(nc -vz consul 8501) 2> /dev/null
        RET=$?
        sleep 2
    done
}

# Function to check if RabbitMQ was initialized
check_rabbitmq()
{
    RABBITMQ_PORT=$(echo ${RABBITMQ_MGT_BASE_URL} | grep -oE "[^:]+$")
    RABBITMQ_URL=$(echo ${RABBITMQ_MGT_BASE_URL} | sed "s/\(:\|\/\)/ /g" | awk '{print $2}')
    # Waiting for RabbitMQ to boot
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of RabbitMQ service startup"
        $(nc -vz ${RABBITMQ_URL} ${RABBITMQ_PORT}) 2> /dev/null
        RET=$?
        sleep 2
    done
}

# Function to check if PMSDBs was initialized
# It's necessary to pass the domain name where is localized the PMSDB,
# this is the first parameter of function
check_ps()
{
    # Awaiting PSDB initialization specified in the first parameter
    RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of $1 service startup"
        $(nc -vz $1 $2) 2> /dev/null
        RET=$?
        sleep 2
    done
}

# Function used to enable and configure certificate issuance
generate_certificates()
{
    # Enable certificate issuer plugin
    vault secrets enable pki 2> /dev/null
    if [ $? = 0 ]; then
      # Changing global value of certificate expiration time
      vault secrets tune -max-lease-ttl=${DEFAULT_MAX_TTL} -default-lease-ttl=${TTL_CERT} pki
      # Enable Vault as CA-Root, which will sign the generated certificates
      vault write pki/root/generate/internal common_name=ocariot ttl=${DEFAULT_MAX_TTL} > /dev/null
    fi

    # Creating role to generate certificates that will
    # be used for account and api-gateway as JWT keys
    vault write pki/roles/jwt-account \
        allowed_domains=jwt-account \
        allow_subdomains=true max_ttl=${TTL_CERT} allow_any_name=true > /dev/null

    # Creating roles to generate certificates that will
    # be used in each service's SSL settings
    local HOSTNAMES=$(ls /etc/vault/policies/ | sed "s/.hcl//g")
    for HOSTNAME in ${HOSTNAMES}; do
        vault write pki/roles/${HOSTNAME} \
            allowed_domains="${HOSTNAME}" \
            allow_subdomains=true max_ttl=${TTL_CERT} allow_any_name=true > /dev/null
    done
}

# Function responsible to establish the plugin
# connection and create a role for respective PSMDB
configure_plugin()
{
    if [ $(echo $1 | grep psmdb) ];then
        # Processing the name of the database passed in the first parameter
        DB=$(echo $1 | sed s/psmdb-//g)
        PORT="27017"
        PLUGIN_NAME="mongodb-database-plugin"
        CONNECTION_URL="mongodb://{{username}}:{{password}}@$1:${PORT}/admin"
        CREATION_STATEMENTS='{ "db": "'${DB}'", "roles": [{ "role": "readWrite" }] }'
        REVOCATION_STATEMENTS='{ "db": "'${DB}'"}'
    fi

    if [ $(echo $1 | grep psmysql) ];then
        # Processing the name of the database passed in the first parameter
        DB=$(echo $1 | sed s/psmysql-//g)
        PORT="3306"
        PLUGIN_NAME="mysql-database-plugin"
        CONNECTION_URL="{{username}}:{{password}}@tcp($1:${PORT})/"
        CREATION_STATEMENTS="CREATE USER '{{name}}'@'%' IDENTIFIED WITH mysql_native_password BY '{{password}}';GRANT ALL ON ${DB}.* TO '{{name}}'@'%';"
        REVOCATION_STATEMENTS=""
    fi

    # Verifying if the PSMDB was already initialized
    check_ps $1 ${PORT}

    # Trying establish connection with actual PSMDB
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting to enable database plugin for $1 service"
        vault write database/config/$1 \
                plugin_name=${PLUGIN_NAME} \
                allowed_roles=${DB}-service \
                connection_url=${CONNECTION_URL} \
                username=$2 \
                password=$3
        RET=$?
        sleep 2
    done

    # Creating the role that will be utilized to request a credential in respective PSMDB
    vault write database/roles/${DB}-service \
        db_name=$1 \
        creation_statements="${CREATION_STATEMENTS}" \
        revocation_statements="${REVOCATION_STATEMENTS}" \
        default_ttl=${TTL_PSMDB_USER} \
        max_ttl=${TTL_PSMDB_USER} > /dev/null
}

# Function used to generate encryption key used to encrypt data
# stored in its PSMDB. In addition, this function generates
# the admin user credentials and activates the database plugin.
configure_ps()
{
    # Enabling the database plugin
    vault secrets enable database

    # Selecting all databases
    local DATABASES=$(echo $(ls /etc/vault/policies/ | sed s/.hcl//g | grep "psmdb\|psmysql"))

    # Creating admin users with its respective credentials
    for DATABASE in ${DATABASES}; do
        if [ $(echo ${DATABASE} | grep psmdb) ];then
          PATH_SECRET="secret"
        fi

        if [ $(echo ${DATABASE} | grep psmysql) ];then
          PATH_SECRET="secret-v1"
        fi

        vault kv get ${PATH_SECRET}/${DATABASE}/credential > /dev/null

        if [ $? = 0 ]; then
          continue
        fi

        # Defining user name based in PSMDB name
        local USER=$(echo ${DATABASE} | sed 's/psmdb-\|psmysql-//g')".app"
        # Generate password for admin user
        local PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

        # Saving the user and password generated as a secret in Vault
        vault kv put ${PATH_SECRET}/${DATABASE}/credential "user"=${USER} "passwd"=${PASSWD} > /dev/null
    done

    for DATABASE in ${DATABASES}; do
        if [ $(echo ${DATABASE} | grep psmdb) ];then
          PATH_SECRET="secret"
        fi

        if [ $(echo ${DATABASE} | grep psmysql) ];then
          PATH_SECRET="secret-v1"
        fi
        # Defining user name based in PSMDB name
        local USER=$(vault kv get -field="user" ${PATH_SECRET}/${DATABASE}/credential)
        # Generate password for admin user
        local PASSWD=$(vault kv get -field="passwd" ${PATH_SECRET}/${DATABASE}/credential)

        # Function responsible to establish the plugin
        # connection and create a role for respective PSMDB
        configure_plugin ${DATABASE} ${USER} ${PASSWD}
    done
}

# Function used to add a Vault CA certificate to the system, with
# this CA certificate Vault becomes trusted.
# It's necessary to enable RabbitMQ plugin
add_certificate()
{
    mkdir -p /usr/share/ca-certificates/extra
    vault read -field="certificate" /pki/cert/ca >> /usr/share/ca-certificates/extra/ca_rabbitmq.crt
    echo "extra/ca_rabbitmq.crt" >> /etc/ca-certificates.conf
    update-ca-certificates
}

# This function generates the admin user
# credentials and active the RabbitMQ plugin.
configure_rabbitmq_plugin()
{
    # Function to check if RabbitMQ was initialized
    check_rabbitmq

    vault read rabbitmq/roles/read_write &> /dev/null

    if [ $? != 0 ]; then
        # Defining username for admin user
        local USER="ocariot"
        # Generate password for admin user
        local PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

        # Saving the username and password as a secret in Vault
        vault kv put secret/rabbitmq/credential "user"=${USER} "passwd"=${PASSWD} > /dev/null

        # Enabling the RabbitMQ plugin
        vault secrets enable rabbitmq
    else
        # Defining username for admin user
        local USER=$(vault kv get -field="user" secret/rabbitmq/credential)
        # Generate password for admin user
        local PASSWD=$(vault kv get -field="passwd" secret/rabbitmq/credential)
    fi

    # Configuring lease settings for generated credentials
    vault write /rabbitmq/config/lease ttl=${TTL_RABBITMQ_USER} max_ttl=${TTL_RABBITMQ_USER}

    # Trying establish connection with RabbitMQ Management
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting to enable plugin for rabbitmq service"
        vault write rabbitmq/config/connection \
            connection_uri="${RABBITMQ_MGT_BASE_URL}" \
            username=${USER} \
            password=${PASSWD} 2> /dev/null
        RET=$?
        sleep 2
    done

    # Creating the role that will be utilized to request a credential
    vault write rabbitmq/roles/read_write \
        vhosts='{"ocariot":{"configure": ".*", "write": ".*", "read": ".*"}}' > /dev/null

}

# Function to remove all leases entered
# in the first parameter of the function
revoke_leases()
{
    # Getting root access token
    ACCESSOR_ROOT=$(vault token lookup | grep accessor | sed 's/accessor*[ \t]*//g')

    # Removing every lease informed in first parameter of
    # revoke_leases () function, except the root token lease
    printf "$1" | sed "/${ACCESSOR_ROOT}/d" | awk 'NR > 2{system("vault token revoke -accessor "$1)}'
}

# Function responsible to create the policies
# that will be used in token generations
generate_policies()
{
    # Loading every policies
    POLICIES_DIRECTORY="/etc/vault/policies/"
    CONTAINERS=$(ls ${POLICIES_DIRECTORY} | sed s/.hcl//g)

    for CONTAINER in ${CONTAINERS};do
      # Creating the policies that will be used in token generations
      # Each police is mapped with the name registered in file
      vault policy write ${CONTAINER} ${POLICIES_DIRECTORY}${CONTAINER}.hcl  > dev/null
    done
}

# Function to create JWT keys that will be requested
# by the Account service and will have the public key
# shared with the Api Gateway service.
create_keys_jwt()
{
    vault kv get secret/api-gateway-service/jwt
    if [ $? = 0 ]; then
      return
    fi

    # Issuing certificate keys that will be used as JWT
    # keys and saving temporarily in /tmp/keys_jwt file
    vault write pki/issue/jwt-account \
        common_name=jwt-account \
        -format="json" > /tmp/keys_jwt

    # Processing private key and placing in PRIVATE_KEY variable
    PRIVATE_KEY=$(echo -e $(cat /tmp/keys_jwt | grep '"private_key":' | sed 's/^[ \t]*"private_key": "//g;s/[,"]//g'))

    # Processing public key and placing in PUBLIC_KEY variable
    PUBLIC_KEY=$(echo -e $(cat /tmp/keys_jwt | grep '"certificate":'  | sed 's/^[ \t]*"certificate": "//g;s/[,"]//g'))

    # Removing temporarily file utilized in request
    rm /tmp/keys_jwt

    # Saving private and public keys in a path accessible for account service
    vault kv put secret/account-service/jwt "private_key"="${PRIVATE_KEY}" "public_key"="${PUBLIC_KEY}"
    # Saving only public key in a path accessible for api gateway service
    vault kv put secret/api-gateway-service/jwt "public_key"="${PUBLIC_KEY}"
}

# Function responsible to encrypt secret
# key that will be request for account service
create_encrypt_secret_key()
{
    vault kv get secret/account-service/encrypt-secret-key
    if [ $? = 0 ]; then
      return
    fi

    # Generating key that will utilized as
    # encrypt secret key in account service
    local KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

    # Saving encrypt key in a path accessible for account service
    vault kv put secret/account-service/encrypt-secret-key "value"="${KEY}"
}

create_keystore_pass()
{
    vault kv get secret/notification-service/keystore_pass
    if [ $? = 0 ]; then
      return
    fi

    KEYSTORE_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)
    vault kv put secret/notification-service/keystore_pass "value"="${KEYSTORE_PASS}"
}

# Function responsible for setting up the
# Vault environment and controlling system startup
main()
{
    # Function to check if vault was initialized
    check_vault

    # Checking if the Vault has been previously started
    local INITIALIZED_BEFORE=$(vault status | grep "Initialized" | awk '{print $2}')

    # If It hasn't been previously started, only is necessary
    # to unseal Vault, revoke the leases
    # previously provided and generate new tokens
    if [[ $INITIALIZED_BEFORE == "false" ]]
    then
        echo "Not previously initialized"

        # Activating the vault and generating unlock keys and root token
        vault operator init -format="table" | grep -E "Unseal Key|Initial Root Token" > /etc/vault/.keys
    else
        echo "Previously initialized"
    fi

    # Function to unseal vault
    unseal

    # Function to check if HA Mode was initialized
    check_ha_mode

    # Authenticating user with root access token
    root_user_authentication

    # Function used to enable and configure certificate issuance
    generate_certificates

    # Function used to add the RabbitMQ CA certificate to the system, with
    # this CA certificate RabbitMQ becomes trusted.
    # Obs: This is necessary to enable RabbitMQ plugin
    add_certificate

    # Enabling secrets enrollment in Vault
    vault secrets enable -version=1 -path=secret-v1/ kv &> /dev/null
    vault secrets enable -version=2 -path=secret/ kv &> /dev/null

    # Getting every access token that will be utilized
    # to revoke the leases previously provided
    TOKENS_TO_REVOKE=$(vault list /auth/token/accessors)

    create_keystore_pass > /dev/null

    # Function to create JWT keys that will be requested
    # by the Account service and will have the public key
    # shared with the Api Gateway service.
    create_keys_jwt > /dev/null

    # Function responsible to encrypt secret
    # key that will be request for account service
    create_encrypt_secret_key > /dev/null

    # Function responsible to create the policies
    # that will be used in token generations
    generate_policies

    echo "Token Generation Enabled"

    # This function generates the admin user
    # credentials and activates the database plugin.
    configure_ps

    # This function generates the admin user
    # credentials and active the RabbitMQ plugin.
    configure_rabbitmq_plugin

    if [[ $INITIALIZED_BEFORE == "true" ]]
    then
        # Function to remove all leases entered
        # in the first parameter of the function
        revoke_leases "${TOKENS_TO_REVOKE}"
    fi

    echo "Stack initialized successfully!!! :)"
    wget -qO - https://pastebin.com/raw/jNnscFJX
}

# Function to check if Consul was initialized
check_consul

# Main Vault configuration stack
main &

# Starting Vault with its configurations
vault server -config=/etc/vault/config.hcl
