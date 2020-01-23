path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-account" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-account/*" {
  capabilities = ["read"]
}
