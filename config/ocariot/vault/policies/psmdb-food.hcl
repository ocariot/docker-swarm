path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-food" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-food/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
