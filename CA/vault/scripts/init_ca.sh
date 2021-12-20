ROOT_TOKEN_PATH=${VAULT_CA_ROOT_TOKEN_PATH-./vault/token}
ROOT_TOKEN_FILE_NAME=${VAULT_CA_ROOT_TOKEN_FILE_NAME-root}
VAULT_TOKEN=$(cat $ROOT_TOKEN_PATH/$ROOT_TOKEN_FILE_NAME)
VAULT_ADDR=${VAULT_ADDR-localhost:7200}
CERTS_DIR="./certs"
CACERT_DIR=$CERTS_DIR/ca
CACERT_FILENAME=ca.crt
INT_CA_CERT_DIR=$CERTS_DIR/intermediate_ca
INT_CA_CSR_FILENAME=intermediate_ca.csr
INT_CA_CERT_FILENAME=intermediate_ca.crt
PKI_ROLES_CONFIG_DIR="./CA/config/roles"
PKI_ROLE_CONSUL_CLUSTER_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/consul-cluster/consul-cluster.json
PKI_ROLE_CONSUL_CLIENT_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/consul-client/consul-client.json
PKI_ROLE_VAULT_CLUSTER_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/vault-cluster/vault-cluster.json
PKI_ROLE_VAULT_CLIENT_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/vault-client/vault-client.json
PKI_ROLE_QKMS_SERVER_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/qkms-server/qkms-server.json
PKI_ROLE_QKMS_CLIENT_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/qkms-client/qkms-client.json
PKI_ROLE_POSTGRES_CONFIG_DIR=$PKI_ROLES_CONFIG_DIR/postgres/postgres.json

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

  rm -rf $CACERT_DIR
  mkdir -p $CACERT_DIR

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"common_name":"clancy.com","ttl":"87600h"}' \
    $VAULT_ADDR/v1/pki/root/generate/internal |
    jq -r ".data.certificate" > $CACERT_DIR/$CACERT_FILENAME
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

  rm -rf $INT_CA_CERT_DIR
  mkdir -p $INT_CA_CERT_DIR

  # vault write -format=json pki_int/intermediate/generate/internal \
  #   common_name="clancy.com Intermediate Authority" |
  #   jq -r '.data.csr' >pki_intermediate.csr
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"common_name": "clancy.com Intermediate Authority"}' \
    $VAULT_ADDR/v1/pki_int/intermediate/generate/internal |
    jq -r '.data.csr' | sed ':a;N;$!ba;s/\n/\\n/g' > $INT_CA_CERT_DIR/$INT_CA_CSR_FILENAME

  PKI_INT_CSR=$(cat $INT_CA_CERT_DIR/$INT_CA_CSR_FILENAME)

  # vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
  #   format=pem_bundle ttl="43800h" |
  #   jq -r '.data.certificate' >intermediate.cert.pem
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "{\"csr\": \"$PKI_INT_CSR\",\"format\": \"pem_bundle\",\"ttl\": \"43800h\"}" \
    $VAULT_ADDR/v1/pki/root/sign-intermediate \
    | jq -r '.data.certificate' | sed ':a;N;$!ba;s/\n/\\n/g' > $INT_CA_CERT_DIR/$INT_CA_CERT_FILENAME

  PKI_INT_CERT=$(cat $INT_CA_CERT_DIR/$INT_CA_CERT_FILENAME)

  # vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "{\"certificate\": \"$PKI_INT_CERT\"}\"}" \
    $VAULT_ADDR/v1/pki_int/intermediate/set-signed
}

create_role() {
  ROLE_NAME=$1
  ROLE_CONFIG_DIR=$2

  # vault write pki_int/roles/$ROLE_NAME \
  #   allowed_domains=$DOMAIN \
  #   allow_subdomains=true \
  #   generate_lease=true \
  #   max_ttl="720h"

  curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data @$ROLE_CONFIG_DIR \
    $VAULT_ADDR/v1/pki_int/roles/$ROLE_NAME
}

request_cert() {
  ROLE_NAME=$1
  CN=$2
  CERTS_PATH=$CERTS_DIR/$3

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

  rm tmp.txt

  echo $tmp_key
}

enable_pki

generate_root_ca_cert

config_cert_urls

generate_int_ca

create_role "consul-cluster-clancy-dot-com" $PKI_ROLE_CONSUL_CLUSTER_CONFIG_DIR
request_cert "consul-cluster-clancy-dot-com" "consul.clancy.com" "consul"

create_role "consul-client-clancy-dot-com" $PKI_ROLE_CONSUL_CLIENT_CONFIG_DIR
request_cert "consul-client-clancy-dot-com" "consul-client.clancy.com" "consul_client"

create_role "vault-cluster-clancy-dot-com" $PKI_ROLE_VAULT_CLUSTER_CONFIG_DIR
request_cert "vault-cluster-clancy-dot-com" "vault.clancy.com" "vault"

create_role "vault-client-clancy-dot-com" $PKI_ROLE_VAULT_CLIENT_CONFIG_DIR
request_cert "vault-client-clancy-dot-com" "vault-client.clancy.com" "vault_client"

create_role "qkms-server-clancy-dot-com" $PKI_ROLE_QKMS_SERVER_CONFIG_DIR
request_cert "qkms-server-clancy-dot-com" "qkms.clancy.com" "qkms"

create_role "qkms-client-clancy-dot-com" $PKI_ROLE_QKMS_CLIENT_CONFIG_DIR
request_cert "qkms-client-clancy-dot-com" "qkms-client.clancy.com" "qkms_client"

create_role "postgres-clancy-dot-com" $PKI_ROLE_POSTGRES_CONFIG_DIR
request_cert "postgres-clancy-dot-com" "postgres.clancy.com" "postgres"
