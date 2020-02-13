path "database/creds/notification-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/notification-service" {
  capabilities = ["read","update"]
}

path "secret/data/notification-service/*" {
  capabilities = ["read"]
}
