#!/bin/sh
TTL_PSMDB_TOKEN="10m"
TTL_SERVICE_TOKEN="87600h"

# Reading the policies related to each service
SERVICE=$(ls /etc/vault/policies/ | sed s/.hcl//g | grep "^$(echo $1 | sed 's/\(ocariot_\|monitor_\|\..*\)//g')")
SERVICE_NAME=$(echo $1 | sed 's/\./_/g')

# Configuring time based in type token
# If the token is for configuration only, the time is 10 minutes.
# If the token is for a service that has continuous  integration with Vault, the time is 10 years.
TIME=${TTL_PSMDB_TOKEN}
if [ $(echo "${SERVICE}" | grep service) ]; then
    TIME=${TTL_SERVICE_TOKEN}
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

    if [ -z "$(vault kv get secret/map-accessor-token 2> /dev/null)" ]; then
      vault kv put secret/map-accessor-token "${SERVICE_NAME}"="${ACCESSOR}" > /dev/null
    else
      vault kv patch secret/map-accessor-token "${SERVICE_NAME}"="${ACCESSOR}" > /dev/null
    fi

    # Exporting generated token to file shared withTOKENS_TO_REVOKE service
    echo "export VAULT_ACCESS_TOKEN=${TOKEN}" > "/etc/vault/.tokens/access-token-${SERVICE}"
fi
