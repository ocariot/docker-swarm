#!/bin/sh

SERVICE_NAME=$(echo $1 | sed 's/\./_/g')

LAST_ACCESSOR_TOKEN=$(vault kv get -field="${SERVICE_NAME}" secret/map-accessor-token/)

if [ "${LAST_ACCESSOR_TOKEN}" ];
then
    VERIFYING_LEASE=$(vault list /auth/token/accessors \
        | grep ${LAST_ACCESSOR_TOKEN})

    if [ "${VERIFYING_LEASE}" ];
    then
        vault token revoke -accessor ${LAST_ACCESSOR_TOKEN}
    fi

    UPDATE_ACCESSORS=$(vault kv get secret/map-accessor-token/ \
        | tail -n +12 | grep -vw ${SERVICE_NAME} \
        | tr -s ' ' | tr ' ' '=')

    if [ -z "${UPDATE_ACCESSORS}" ];then
      vault kv metadata delete secret/map-accessor-token
    else
      vault kv put secret/map-accessor-token/ ${UPDATE_ACCESSORS}
    fi
fi
