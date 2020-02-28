#!/bin/sh
TTL_PSMDB_TOKEN="10m"
TTL_SERVICE_TOKEN="87600h"
ACCESSOR_TOKEN_FILE="/tmp/accessor-token"

if [ ! $(find /tmp -maxdepth 1 -name accessor-token) ]
then
    touch /tmp/accessor-token
fi

# Reading the policies related to each service
SERVICE=$(ls /etc/vault/policies/ | sed s/.hcl//g | grep "^$(echo $1 | sed 's/\(ocariot_\|monitor_\|\..*\)//g')")
SERVICE_NAME=$(echo $1 | sed 's/\./_/g;s/_[^_]*$//')

# Configuring time based in type token
# If the token is for configuration only, the time is 10 minutes.
# If the token is for a service that has continuous  integration with Vault, the time is 10 years.
TIME=${TTL_PSMDB_TOKEN}
if [ $(echo "${SERVICE}" | grep service) ]; then
    TIME=${TTL_SERVICE_TOKEN}
fi

LAST_ACCESSOR_TOKEN=$(cat "${ACCESSOR_TOKEN_FILE}" \
    | grep "${SERVICE_NAME}" \
    | awk '{print $2}')

if [ "${LAST_ACCESSOR_TOKEN}" ];
then
    VERIFYING_LEASE=$(vault list /auth/token/accessors \
        | grep ${LAST_ACCESSOR_TOKEN})

    if [ "${VERIFYING_LEASE}" ];
    then
        vault token revoke -accessor ${LAST_ACCESSOR_TOKEN}
    fi

    sed -i "/${SERVICE_NAME}/d" "${ACCESSOR_TOKEN_FILE}"
fi

if [ "${SERVICE}" ];
then
    # Token Generation
    TOKEN=$(vault token create -policy="${SERVICE}" \
        -renewable=false \
        -period=${TIME} \
        -display-name="${SERVICE}" \
        -field="token")

    ACCESSOR=$(vault token lookup ${TOKEN} \
        | grep accessor \
        | sed 's/accessor*[ \t]*//g')

    echo "${SERVICE_NAME} ${ACCESSOR}" >> ${ACCESSOR_TOKEN_FILE}

    # Exporting generated token to file shared withTOKENS_TO_REVOKE service
    echo "export VAULT_ACCESS_TOKEN=${TOKEN}" > "/etc/vault/.tokens/access-token-${SERVICE}"
fi
