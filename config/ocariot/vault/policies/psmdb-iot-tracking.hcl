path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-iot-tracking" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-iot-tracking/*" {
  capabilities = ["create", "read"]
}
