path "database/creds/account-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/account-service" {
  capabilities = ["read","update"]
}

path "secret/data/account-service/*" {
  capabilities = ["read"]
}
