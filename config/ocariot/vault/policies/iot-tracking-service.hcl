path "database/creds/iot-tracking-service" {
  capabilities = ["read"]
}

path "rabbitmq/creds/read_write" {
  capabilities = ["read"]
}

path "pki/issue/iot-tracking-service" {
  capabilities = ["read","update"]
}
