path "database/creds/ds-agent-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/ds-agent-service" {
  capabilities = ["read","update"]
}
