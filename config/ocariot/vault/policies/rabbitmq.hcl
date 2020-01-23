path "pki/issue/rabbitmq" {
  capabilities = ["read","update"]
}

path "secret/data/rabbitmq/*" {
  capabilities = ["read"]
}
