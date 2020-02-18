path "database/creds/missions-service" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/missions-service" {
  capabilities = ["read","update"]
}
