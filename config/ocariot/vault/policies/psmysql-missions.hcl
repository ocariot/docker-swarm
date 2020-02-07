path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmysql-missions" {
  capabilities = ["read","update"]
}

path "secret-v1/psmysql-missions/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
