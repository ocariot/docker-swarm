path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-quest" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-quest/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
