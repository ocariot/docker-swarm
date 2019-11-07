path "database/creds/food-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/food-service" {
  capabilities = ["read","update"]
}
