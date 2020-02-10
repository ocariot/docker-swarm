path "database/creds/missions-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/missions-service" {
  capabilities = ["read","update"]
}
