#!/bin/sh
ACCESSOR_TOKEN_FILE="/tmp/accessor-token"

if [ ! $(find /tmp -maxdepth 1 -name accessor-token) ]
then
    exit
fi

SERVICE_NAME=$(echo $1 | sed 's/\./_/g')

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
