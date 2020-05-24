path "database/creds/dt-process-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/dt-process-service" {
  capabilities = ["read","update"]
}
