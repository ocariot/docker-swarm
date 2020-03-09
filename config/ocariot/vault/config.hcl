storage "consul" {
  address = "https://consul:8501"
  advertise_addr = "https://consul:8300"
  path    = "vault/"
  scheme        = "https"
  tls_ca_file   = "/etc/consul/.certs/ca.crt"
  tls_cert_file = "/etc/consul/.certs/client.key.pub"
  tls_key_file  = "/etc/consul/.certs/client.key"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 0
  scheme        = "https"
  tls_client_ca_file = "/etc/vault/.certs/ca.crt"
  tls_cert_file = "/etc/vault/.certs/server.cert"
  tls_key_file  = "/etc/vault/.certs/server.key"
}

max_lease_ttl = "87600h"

disable_mlock = true

ui = true
