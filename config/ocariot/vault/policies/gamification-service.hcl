path "database/creds/gamification-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/gamification-service" {
  capabilities = ["read","update"]
}
