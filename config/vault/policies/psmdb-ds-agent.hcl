path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-ds-agent" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-ds-agent/*" {
  capabilities = ["read"]
}
