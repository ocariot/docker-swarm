#!/usr/bin/env bash

cat << EOF > /tmp/generate_tokens.sh
#!/bin/sh
TTL_PSMDB_TOKEN="10m"
TTL_SERVICE_TOKEN="87600h"
ACCESSOR_TOKEN_FILE="/tmp/accessor-token"

if [ ! \$(find /tmp -maxdepth 1 -name accessor-token) ]
then
    touch /tmp/accessor-token
fi

# Reading the policies related to each service
SERVICE=\$(ls /etc/vault/policies/ | sed s/.hcl//g | grep "^\$(echo \$1 | sed 's/\(ocariot_\|\..*\)//g')")
SERVICE_NAME=\$(echo \$1 | sed 's/\./_/g;s/_[^_]*$//')

# Configuring time based in type token
# If the token is for configuration only, the time is 10 minutes.
# If the token is for a service that has continuous  integration with Vault, the time is 10 years.
TIME=\${TTL_PSMDB_TOKEN}
if [ \$(echo "\${SERVICE}" | grep service) ]; then
    TIME=\${TTL_SERVICE_TOKEN}
fi

LAST_ACCESSOR_TOKEN=\$(cat "\${ACCESSOR_TOKEN_FILE}" \\
    | grep "\${SERVICE_NAME}" \\
    | awk '{print \$2}')

if [ "\${LAST_ACCESSOR_TOKEN}" ];
then
    VERIFYING_LEASE=\$(vault list /auth/token/accessors \\
        | grep \${LAST_ACCESSOR_TOKEN})

    if [ "\${VERIFYING_LEASE}" ];
    then
        vault token revoke -accessor \${LAST_ACCESSOR_TOKEN}
    fi

    sed -i "/\${SERVICE_NAME}/d" "\${ACCESSOR_TOKEN_FILE}"
fi

if [ "\${SERVICE}" ];
then
    # Token Generation
    TOKEN=\$(vault token create -policy="\${SERVICE}" \\
        -renewable=false \\
        -period=\${TIME} \\
        -display-name="\${SERVICE}" \\
        -field="token")

    ACCESSOR=\$(vault token lookup \${TOKEN} \\
        | grep accessor \\
        | sed 's/accessor*[ \t]*//g')

    echo "\${SERVICE_NAME} \${ACCESSOR}" >> \${ACCESSOR_TOKEN_FILE}

    # Exporting generated token to file shared withTOKENS_TO_REVOKE service
    echo "export VAULT_ACCESS_TOKEN=\${TOKEN}" > "/etc/vault/tokens/access-token-\${SERVICE}"
fi
EOF

cat << EOF > /tmp/remove_tokens.sh
#!/bin/sh
ACCESSOR_TOKEN_FILE="/tmp/accessor-token"

if [ ! \$(find /tmp -maxdepth 1 -name accessor-token) ]
then
    exit
fi

SERVICE_NAME=\$(echo \$1 | sed 's/\./_/g;s/_[^_]*$//')

LAST_ACCESSOR_TOKEN=\$(cat "\${ACCESSOR_TOKEN_FILE}" \\
    | grep "\${SERVICE_NAME}" \\
    | awk '{print \$2}')

if [ "\${LAST_ACCESSOR_TOKEN}" ];
then
    VERIFYING_LEASE=\$(vault list /auth/token/accessors \\
        | grep \${LAST_ACCESSOR_TOKEN})

    if [ "\${VERIFYING_LEASE}" ];
    then
        vault token revoke -accessor \${LAST_ACCESSOR_TOKEN}
    fi

    sed -i "/\${SERVICE_NAME}/d" "\${ACCESSOR_TOKEN_FILE}"
fi
EOF

TEMP_FILE=$(mktemp)
check_vault()
{
    echo $(docker service logs ocariot_vault >& ${TEMP_FILE};
        grep -c "Token Generation Enabled" ${TEMP_FILE})
}

execute_script()
{
    echo "********** $(check_vault) **********"

    RET=$(check_vault)
    while [[ ${RET} != 1 ]];
    do
        if [ "$(docker stack ls | grep -w ocariot)" = "" ];
        then
            return
        fi
        RET=$(check_vault)
        sleep 3
    done

    echo "Stack was initialized successfully"

    STACK_ID=$(docker stack ps ocariot --format "{{.ID}}" --filter "name=ocariot_vault" --filter "desired-state=running")

    CONTAINER_ID=$(docker ps --format {{.ID}} --filter "name=${STACK_ID}")
    echo "Transferindo script $2"
    docker cp /tmp/$2.sh ${CONTAINER_ID}:/tmp/$2.sh &&
    echo "Executando script $2 para: $1"
    docker exec -t ${CONTAINER_ID} chmod +x /tmp/$2.sh &&
    docker exec -t ${CONTAINER_ID} /tmp/$2.sh $1
}

PROCESSES_NUMBER=$(ps aux \
    | grep -w service_monitor.sh \
    | sed '/grep/d' \
    | wc -l)

if [ "${PROCESSES_NUMBER}" -gt 2 ]; then
    echo "Sevice monitor already initialized"
    exit
fi

docker events \
    --filter type=container \
    --filter 'event=destroy' \
    --filter 'event=create' \
    --format '{{json .Actor.Attributes.name}} {{json .Action}}' \
    | while read event; do
        docker stack ps ocariot &> /dev/null
        if [ $? = 0  ];
        then
            EVENT=$(echo ${event} \
                    | sed 's/"//g')
            CONTAINER_NAME=$(echo ${EVENT} | awk '{print $1}' | grep ocariot)
            ACTION=$(echo ${EVENT} | awk '{print $2}')

            SCRIPT_NAME="generate_tokens"
            if [ "${ACTION}" = "destroy" ];
            then
                SCRIPT_NAME="remove_tokens"
            fi
            execute_script ${CONTAINER_NAME} ${SCRIPT_NAME}
        fi
    done
