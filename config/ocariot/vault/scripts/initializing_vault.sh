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
    # Waiting for RabbitMQ to boot
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of RabbitMQ service startup"
        $(nc -vz $(echo ${RABBITMQ_MGT_BASE_URL} | grep -oE '[^/]*$') ${RABBITMQ_MGT_PORT}) 2> /dev/null
        RET=$?
        sleep 2
    done
}

# Function to check if PMSDBs was initialized
# It's necessary to pass the domain name where is localized the PMSDB,
# this is the first parameter of function
check_psmdbs()
{
    # Awaiting PSDB initialization specified in the first parameter
    RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting for confirmation of $1 service startup"
        $(nc -vz $1 27017) 2> /dev/null
        RET=$?
        sleep 2
    done
}

# Function used to enable and configure certificate issuance
generate_certificates()
{
    # Enable certificate issuer plugin
    vault secrets enable pki
    # Changing global value of certificate expiration time
    vault secrets tune -max-lease-ttl=${DEFAULT_MAX_TTL} -default-lease-ttl=${TTL_CERT} pki
    # Enable Vault as CA-Root, which will sign the generated certificates
    vault write pki/root/generate/internal common_name=ocariot ttl=${DEFAULT_MAX_TTL} > /dev/null

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
configure_psmdb_plugin()
{
    # Processing the name of the database passed in the first parameter
    local DB=$(echo $1 | sed s/psmdb-//g)

    # Verifying if the PSMDB was already initialized
    check_psmdbs $1

    # Trying establish connection with actual PSMDB
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting to enable database plugin for $1 service"
        vault write database/config/$1 \
                plugin_name=mongodb-database-plugin \
                allowed_roles=${DB}-service \
                connection_url="mongodb://{{username}}:{{password}}@$1:27017/admin" \
                username=$2 \
                password=$3 2> /dev/null
        RET=$?
        sleep 2
    done

    # Creating the role that will be utilized to request a credential in respective PSMDB
    vault write database/roles/${DB}-service \
        db_name=$1 \
        creation_statements='{ "db": "'${DB}'", "roles": [{ "role": "readWrite" }] }' \
        revocation_statements='{ "db": "'${DB}'"}' \
        default_ttl=${TTL_PSMDB_USER} \
        max_ttl=${TTL_PSMDB_USER} > /dev/null
}

# Function used to generate encryption key used to encrypt data
# stored in its PSMDB. In addition, this function generates
# the admin user credentials and activates the database plugin.
configure_psmdbs()
{
    # Enabling the database plugin
    vault secrets enable database

    # Selecting all databases
    local DATABASES=$(echo $(ls /etc/vault/policies/ | sed s/.hcl//g | grep psmdb))

    # Creating admin users with its respective credentials
    for DATABASE in ${DATABASES}; do
        # Generating encryption key
        ENCRYPTION_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)
        # Saving the encrypt key as a secret in Vault
        vault kv put secret/${DATABASE}/encryptionKey value=${ENCRYPTION_KEY} > /dev/null

        # Defining user name based in PSMDB name
        local USER=$(echo ${DATABASE} | sed s/psmdb-//g)".app"
        # Generate password for admin user
        local PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

        # Saving the user and password generated as a secret in Vault
        vault kv put secret/${DATABASE}/credential "user"=${USER} "passwd"=${PASSWD} > /dev/null
    done

    for DATABASE in ${DATABASES}; do
        # Defining user name based in PSMDB name
        local USER=$(vault kv get -field="user" secret/${DATABASE}/credential)
        # Generate password for admin user
        local PASSWD=$(vault kv get -field="passwd" secret/${DATABASE}/credential)

        # Function responsible to establish the plugin
        # connection and create a role for respective PSMDB
        configure_psmdb_plugin ${DATABASE} ${USER} ${PASSWD}
    done
}

# Function used to add a Vault CA certificate to the system, with
# this CA certificate Vault becomes trusted.
# It's necessary to enable RabbitMQ plugin
add_certificate()
{
    cat /etc/vault/.certs/ca.crt >> /etc/ssl/certs/ca-certificates.crt
}

# This function generates the admin user
# credentials and active the RabbitMQ plugin.
configure_rabbitmq_plugin()
{
    # Function used to add the Vault CA certificate to the system, with
    # this CA certificate Vault becomes trusted.
    # Obs: This is necessary to enable RabbitMQ plugin
    add_certificate

    # Function to check if RabbitMQ was initialized
    check_rabbitmq

    # Defining username for admin user
    local USER="ocariot"
    # Generate password for admin user
    local PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

    # Saving the username and password as a secret in Vault
    vault kv put secret/rabbitmq/credential "user"=${USER} "passwd"=${PASSWD} > /dev/null

    # Enabling the RabbitMQ plugin
    vault secrets enable rabbitmq

    # Configuring lease settings for generated credentials
    vault write /rabbitmq/config/lease ttl=${TTL_RABBITMQ_USER} max_ttl=${TTL_RABBITMQ_USER}

    # Trying establish connection with RabbitMQ Management
    local RET=1
    while [[ $RET -ne 0 ]]; do
        echo "=> Waiting to enable plugin for rabbitmq service"
        vault write rabbitmq/config/connection \
            connection_uri="${RABBITMQ_MGT_BASE_URL}:${RABBITMQ_MGT_PORT}" \
            username=${USER} \
            password=${PASSWD} 2> /dev/null
        RET=$?
        sleep 2
    done

    # Creating the role that will be utilized to request a credential
    vault write rabbitmq/roles/read_write \
        vhosts='{"ocariot":{"configure": ".*", "write": ".*", "read": ".*"}}' > /dev/null

    echo "Stack initialized successfully!!! :)"
    wget -qO - https://pastebin.com/raw/jNnscFJX
}

# Function to remove all leases entered
# in the first parameter of the function
revoke_leases()
{
    # Function to check if RabbitMQ was initialized
    check_rabbitmq

    # Checking if all databases was initialized
    local DATABASES=$(echo $(ls /etc/vault/policies/ | sed s/.hcl//g | grep psmdb))
    for DATABASE in ${DATABASES}; do
        # Function to check if PMSDBs was initialized
        # It's necessary to pass the domain name where is localized the PMSDB,
        # this is the first parameter of function
        check_psmdbs ${DATABASE}
    done

    # Getting root access token
    ACCESSOR_ROOT=$(vault token lookup | grep accessor | sed 's/accessor*[ \t]*//g')

    # Removing every lease informed in first parameter of
    # revoke_leases () function, except the root token lease
    printf "$1" | sed "/${ACCESSOR_ROOT}/d" | awk 'NR > 2{system("vault token revoke -accessor "$1)}'
}

# Function responsible for setting up the
# Vault environment and controlling system startup
configure_vault()
{
    # Function to check if vault was initialized
    check_vault

    # Checking if the Vault has been previously started
    local INITIALIZED_BEFORE=$(vault status | grep "Initialized" | awk '{print $2}')

    # If It has been previously started, only is necessary
    # to unseal Vault, revoke the leases
    # previously provided and generate new tokens
    if [[ $INITIALIZED_BEFORE == "true" ]]
    then
        echo "Previously initialized"

        # Function to unseal vault
        unseal

        # Function to check if HA Mode was initialized
        check_ha_mode

        # Authenticating user with root access token
        root_user_authentication

        # Function used to add a Vault CA certificate to the system, with
        # this CA certificate Vault becomes trusted.
        # It's necessary to enable RabbitMQ plugin
        add_certificate

        # Getting every access token that will be utilized
        # to revoke the leases previously provided
        TOKENS_TO_REVOKE=$(vault list /auth/token/accessors)

        echo "Token Generation Enabled"


        # Function to remove all leases entered
        # in the first parameter of the function
        revoke_leases "${TOKENS_TO_REVOKE}"

        echo "Stack initialized successfully!!! :)"
        wget -qO - https://pastebin.com/raw/jNnscFJX

        # Finishing the script execution
        exit
    fi

    echo "Not previously initialized"

    # Activating the vault and generating unlock keys and root token
    vault operator init -format="table" | grep -E "Unseal Key|Initial Root Token" > /etc/vault/.keys

    # Function to unseal vault
    unseal

    # Function to check if HA Mode was initialized
    check_ha_mode

    # Authenticating user with root access token
    root_user_authentication

    # Enabling secrets enrollment in Vault
    vault secrets enable -path=secret/ kv-v2
}

# Function responsible to create the policies
# that will be used in token generations
generate_policies()
{
    # Loading every policies
    local CONTAINERS=$(ls /etc/vault/policies/ | sed s/.hcl//g)

    # Creating the policies that will be used in token generations
    # Each police is mapped with the name registered in file
    echo ${CONTAINERS} | awk '{ for(file=1; file<=NF; file++) {
    system("vault policy write " $file " /etc/vault/policies/"$file".hcl")
    } }' > dev/null

}

# Function to create JWT keys that will be requested
# by the Account service and will have the public key
# shared with the Api Gateway service.
create_keys_jwt()
{
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
    # Generating key that will utilized as
    # encrypt secret key in account service
    local KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-31} | head -n 1 | base64)

    # Saving encrypt key in a path accessible for account service
    vault kv put secret/account-service/encrypt-secret-key "value"="${KEY}"
}

# Main Vault configuration stack
main()
{
    # Function responsible for setting up the
    # Vault environment and controlling system startup
    configure_vault

    # Function used to enable and configure certificate issuance
    generate_certificates

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

    # Function used to generate encryption key used to encrypt data
    # stored in its PSMDB. In addition, this function generates
    # the admin user credentials and activates the database plugin.
    configure_psmdbs

    # This function generates the admin user
    # credentials and active the RabbitMQ plugin.
    configure_rabbitmq_plugin
}

# Function to check if Consul was initialized
check_consul

# Main Vault configuration stack
main &

# Starting Vault with its configurations
vault server -config=/etc/vault/config.hcl
