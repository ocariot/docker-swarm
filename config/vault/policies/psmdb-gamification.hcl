path "secret/data/vault/ca" {
  capabilities = ["read"]
}

path "pki/issue/psmdb-gamification" {
  capabilities = ["read","update"]
}

path "secret/data/psmdb-gamification/*" {
  capabilities = ["read"]
}
