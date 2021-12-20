VAULT_TOKEN=s.d4tv7z21OyaTPr1v7yRQXaTl
VAULT_ADDR=${VAULT_ADDR-localhost:7200}


vault_post_cmd() {
  path=$1
  data=$2

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    $VAULT_ADDR/$1 \
    --data $2
}

enable_pki() {
  # vault secrets enable pki
  vault_post_cmd 'v1/sys/mounts/pki' '{"type":"pki"}'

  # vault secrets tune -max-lease-ttl=87600h pki
  vault_post_cmd 'v1/sys/mounts/pki/tune' '{"max_lease_ttl":"87600h"}'
}

generate_root_ca_cert() {
  # vault write -field=certificate pki/root/generate/internal \
  #   common_name="clancy.com" \
  #   ttl=87600h >CA_cert.crt

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"common_name":"clancy.com","ttl":"87600h"}' \
    $VAULT_ADDR/v1/pki/root/generate/internal |
    jq -r ".data.certificate" >CA_cert.crt
}

config_cert_urls() {
  # vault write pki/config/urls \
  #   issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
  #   crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"issuing_certificates": "'${VAULT_ADDR}'/v1/pki/ca","crl_distribution_points": "'${VAULT_ADDR}'/v1/pki/crl"}' \
    $VAULT_ADDR/v1/pki/config/urls
}

generate_int_ca() {
  # vault secrets enable -path=pki_int pki
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type":"pki"}' \
    $VAULT_ADDR/v1/sys/mounts/pki_int

  # vault secrets tune -max-lease-ttl=43800h pki_int
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"max_lease_ttl":"43800h"}' \
    $VAULT_ADDR/v1/sys/mounts/pki_int/tune

  # vault write -format=json pki_int/intermediate/generate/internal \
  #   common_name="clancy.com Intermediate Authority" |
  #   jq -r '.data.csr' >pki_intermediate.csr
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"common_name": "clancy.com Intermediate Authority"}' \
    $VAULT_ADDR/v1/pki_int/intermediate/generate/internal |
    jq -r '.data.csr' >pki_intermediate.csr
  PKI_INT_CSR=$(cat pki_intermediate.csr)

  # echo '{"csr": "'${PKI_INT_CSR}'","format": "pem_bundle","ttl": "43800h"}'

  # vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
  #   format=pem_bundle ttl="43800h" |
  #   jq -r '.data.certificate' >intermediate.cert.pem
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"csr": "-----BEGIN CERTIFICATE REQUEST-----\nMIICcTCCAVkCAQAwLDEqMCgGA1UEAxMhY2xhbmN5LmNvbSBJbnRlcm1lZGlhdGUg\nQXV0aG9yaXR5MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnOWmdP0G\nyd9hwjFXI1QrlcFjcsBGsiLArET+LJN+tyXZH7fH7bX5Dn/ut6EH2Dr69wL1TGC1\nRrRXgYWGvKwETAkHJl2OiSeM5pLggRulsr8xMPw8tePztaNhbnQDHMj8+rNLlB3V\nzDx1gXMK7+w/zcPlgWo+R9pgydUhC/E7IqpNIh2AOdfHKIyTbNVEYcK6kE5WSe62\nOzTXD2OoJl34ZVehoyGjGy5Yx8YVzPyS4Xptp8C9Edo9oCAu9N9z1DeW/VKEkYQe\nIKikXLSEi2JT0iKVO4Mly1zDpTOfzmrphxj9agLJkT8Po+pFKbZjFI5QWlG+WdG9\nFTr3vDUp4hSkowIDAQABoAAwDQYJKoZIhvcNAQELBQADggEBAHm30i7aJJTLcHnR\nQ6eCtOzlGKI1nz4coYOZagWEV4jMt8Kj3OhoBuGw6jZDWF+IQZ7j5x6+eSbnZ8D7\njjT0dAcHpehNXfKB5FL1PCqiVbWdiT6yiP84C/ElLGztBxpQWWIzcWoHQx84/ZqS\nnmYKZ5/h38YJolCLiiuqoaGlPQMl/7Xl7viOJ0vk3DDUu55llbK9CyVM0WSmPcpi\nKaw/CflhMW0ukyaRTAGZ4trBiNxctctdtDNAvRzTSauCifiJSJ8bwkMzU92kG15o\nT8x5hgQdxb1PLjm8y6JKP4uSD3AKq8dl//tmAZ8WofQivwRiysTXAZ/jvRnurNQX\n7qU/Fyc=\n-----END CERTIFICATE REQUEST-----\n","format": "pem_bundle","ttl": "43800h"}' \
    $VAULT_ADDR/v1/pki/root/sign-intermediate |
    jq -r '.data.certificate' >intermediate.cert.pem

  # PKI_INT_CERT=$(cat intermediate.cert.pem)
  # PKI_INT_CERT=$($PKI_INT_CSR | sed ':a;N;$!ba;s/\n/\\\\n/g')
  # echo '{"certificate": "'${PKI_INT_CERT}'"}'

  # vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"certificate": "-----BEGIN CERTIFICATE-----\nMIIDljCCAn6gAwIBAgIUKs9FU+DNXPJuu39Y/gl8ig6HyYswDQYJKoZIhvcNAQEL\nBQAwFTETMBEGA1UEAxMKY2xhbmN5LmNvbTAeFw0yMTEyMjAwNTI1MTlaFw0yNjEy\nMTkwNTI1NDlaMCwxKjAoBgNVBAMTIWNsYW5jeS5jb20gSW50ZXJtZWRpYXRlIEF1\ndGhvcml0eTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJzlpnT9Bsnf\nYcIxVyNUK5XBY3LARrIiwKxE/iyTfrcl2R+3x+21+Q5/7rehB9g6+vcC9UxgtUa0\nV4GFhrysBEwJByZdjoknjOaS4IEbpbK/MTD8PLXj87WjYW50AxzI/PqzS5Qd1cw8\ndYFzCu/sP83D5YFqPkfaYMnVIQvxOyKqTSIdgDnXxyiMk2zVRGHCupBOVknutjs0\n1w9jqCZd+GVXoaMhoxsuWMfGFcz8kuF6bafAvRHaPaAgLvTfc9Q3lv1ShJGEHiCo\npFy0hItiU9IilTuDJctcw6Uzn85q6YcY/WoCyZE/D6PqRSm2YxSOUFpRvlnRvRU6\n97w1KeIUpKMCAwEAAaOBxjCBwzAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUw\nAwEB/zAdBgNVHQ4EFgQU9ETPhdikckcqOgnP+ybcLvBCZ94wHwYDVR0jBBgwFoAU\ngeD7qy+fPSLiKav+r7Cl5neRYCMwNAYIKwYBBQUHAQEEKDAmMCQGCCsGAQUFBzAC\nhhhsb2NhbGhvc3Q6NzIwMC92MS9wa2kvY2EwKgYDVR0fBCMwITAfoB2gG4YZbG9j\nYWxob3N0OjcyMDAvdjEvcGtpL2NybDANBgkqhkiG9w0BAQsFAAOCAQEAgfcemD4Z\nChHvCJBqhEmFmPtGnwkNpU7I7cxcxsh8amSvXCM5DqklkWr60/7/SuqAhFi1Bd1+\nA5fNZpSU461LhOLRimHWp99HGC0sV4n2NmlUYYcShh3CdQeXGwIuZyYV7ZKssYbA\nBYrFsBxuftkfD1CYuKDIe5GtC3WHFSoPuxL7Z4swu6CpopnSRTZ5HBkSCG6wTPjV\n3VuaJia0zOlPiQZi/IWyLBMxUCHstGCMF+2lfWlgWCdNjfjYQYki/HadIqIKIF/y\nlMvRKl2oHwc3P9RHz1r+VaYe4StYKPGu3LEnek6BTcDncYbLKL7SU00UWbQMh0K5\nBgNRzz7srWlJYw==\n-----END CERTIFICATE-----\n"}' \
    $VAULT_ADDR/v1/pki_int/intermediate/set-signed
}

create_role() {
  ROLE_NAME=$1
  DOMAIN=$2

  # vault write pki_int/roles/$ROLE_NAME \
  #   allowed_domains=$DOMAIN \
  #   allow_subdomains=true \
  #   generate_lease=true \
  #   max_ttl="720h"

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"allowed_domains": "'$DOMAIN'","allow_subdomains": true, "allow_bare_domains": true, "allow_glob_domains": true, "max_ttl": "720h"}' \
    $VAULT_ADDR/v1/pki_int/roles/$ROLE_NAME
}

request_cert() {
  ROLE_NAME=$1
  CN=$2
  CERTS_PATH=$3

  # vault write pki_int/issue/consul-dc1 \
  #   common_name="server.dc1.consul" \
  #   ttl="24h" | tee consul-certs.txt

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"common_name": "'$CN'", "ttl": "2400h"}' \
    $VAULT_ADDR/v1/pki_int/issue/$ROLE_NAME |
    jq .'data' >tmp.txt

  rm -rf $CERTS_PATH
  mkdir -p $CERTS_PATH

  $(cat tmp.txt | jq .private_key | tr -d '"' | awk '{gsub("\\\\n","\n")};1' | tee $CERTS_PATH/tls.key)
  $(cat tmp.txt | jq .certificate | tr -d '"' | awk '{gsub("\\\\n","\n")};1' | tee $CERTS_PATH/tls.crt)
  $(cat tmp.txt | jq .issuing_ca | tr -d '"' | awk '{gsub("\\\\n","\n")};1' | tee $CERTS_PATH/ca.crt)
  $(cat tmp.txt | jq .ca_chain | tr -d '[' | tr -d '"' | tr -d ']' | awk '{gsub("\\\\n","\n")};1' | tee $CERTS_PATH/chain.crt)

  echo $tmp_key
}

# enable_pki

# generate_root_ca_cert

# config_cert_urls

# generate_int_ca

create_role "clancy-dot-com" "clancy.com"

request_cert "clancy-dot-com" "consul.clancy.com" "certs/consul"
request_cert "clancy-dot-com" "consul-client.clancy.com" "certs/consul_client"
request_cert "clancy-dot-com" "vault.clancy.com" "certs/vault"
request_cert "clancy-dot-com" "vault-client.clancy.com" "certs/vault_client"
request_cert "clancy-dot-com" "qkms.clancy.com" "certs/qkms"
request_cert "clancy-dot-com" "qkms-client.clancy.com" "certs/qkms_client"
request_cert "clancy-dot-com" "postgres.clancy.com" "certs/postgres"
