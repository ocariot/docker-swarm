path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-dt-process" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-dt-process/*" {
  capabilities = ["create", "read"]
}
