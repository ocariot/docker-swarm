path "secret/data/api-gateway-service/*" {
  capabilities = ["read"]
}

path "pki/issue/api-gateway-service" {
  capabilities = ["read","update"]
}

path "pki/roles/devices" {
  capabilities = ["read", "update", "list"]
}

path "pki/sign/devices" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/revoke" {
  capabilities = ["create", "read", "update", "delete", "list"]
}