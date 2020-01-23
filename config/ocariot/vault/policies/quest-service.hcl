path "database/creds/quest-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/quest-service" {
  capabilities = ["read","update"]
}
