VAULT_CA_CERT="./certs/vault_client/ca.crt"
VAULT_CLIENT_CERT="./certs/vault_client/tls.crt"
VAULT_CLIENT_KEY="./certs/vault_client/tls.key"
VAULT_ADDR=${VAULT_ADDR-https://localhost:8200}
PLUGIN_PATH=${PLUGIN_PATH-/vault/plugins}
PLUGIN_MOUNT_PATH=${PLUGIN_MOUNT_PATH-quorum}
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH-./vault/token}
VAULT_TOKEN_FILE_NAME=${VAULT_TOKEN_FILE_NAME-root}
UNSEAL_KEYS_PATH=${UNSEAL_KEYS_PATH-./vault/unseal}
UNSEAL_KEYS_FILE_NAME=${UNSEAL_KEYS_FILE_NAME-unseal_keys}
QKM_TOKEN_PATH=${QKM_TOKEN_PATH-./vault/token}
QKM_TOKEN_FILE_NAME=${QKM_TOKEN_FILE_NAME-qkm_token}
PLUGIN_FILE=./vault/plugins/quorum-hashicorp-vault-plugin

echo "[PLUGIN] Initializing Vault: ${VAULT_ADDR}"
init_vault() {
  curl -k -s --cacert $VAULT_CA_CERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"secret_shares": 7, "secret_threshold": 4}' ${VAULT_ADDR}/v1/sys/init >response.json

  VAULT_TOKEN=$(cat response.json | jq .root_token | tr -d '"')
  UNSEAL_KEYS=$(cat response.json | jq .keys)
  UNSEAL_KEY_0=$(cat response.json | jq .keys | jq '.[0]')
  UNSEAL_KEY_1=$(cat response.json | jq .keys | jq '.[1]')
  UNSEAL_KEY_2=$(cat response.json | jq .keys | jq '.[2]')
  UNSEAL_KEY_3=$(cat response.json | jq .keys | jq '.[3]')

  ERRORS=$(cat response.json | jq .errors | jq '.[0]')
  if [ "$UNSEAL_KEYS" = "null" ]; then
    echo "[CA] cannot retrieve unseal key: $ERRORS"
    exit 1
  fi

  if [ -n "$VAULT_TOKEN" ]; then
    echo "[CA] Root token saved in ${VAULT_TOKEN_PATH}"
    mkdir -p ${VAULT_TOKEN_PATH}
    echo "$VAULT_TOKEN" >${VAULT_TOKEN_PATH}/${VAULT_TOKEN_FILE_NAME}
  fi

  if [ -n "$UNSEAL_KEYS" ]; then
    echo "[PLUGIN] Unseal_Keys saved in ${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}"
    mkdir -p ${UNSEAL_KEYS_PATH}
    echo "$UNSEAL_KEYS" >${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}
  fi

  rm response.json
}

unseal_vault() {
  curl -k -s --cacert $VAULT_CA_CERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"key": '${UNSEAL_KEY_0}'}' ${VAULT_ADDR}/v1/sys/unseal

  curl -k -s --cacert $VAULT_CA_CERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"key": '${UNSEAL_KEY_1}'}' ${VAULT_ADDR}/v1/sys/unseal

  curl -k -s --cacert $VAULT_CA_CERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"key": '${UNSEAL_KEY_2}'}' ${VAULT_ADDR}/v1/sys/unseal

  curl -k -s --cacert $VAULT_CA_CERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"key": '${UNSEAL_KEY_3}'}' ${VAULT_ADDR}/v1/sys/unseal
}

enable_kv2_key_engine() {
  curl -k -s --cacert $VAULT_CA_CERT --header "X-Vault-Token: ${VAULT_TOKEN}" --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"type": "kv-v2", "config": {"force_no_cache": true} }' \
    ${VAULT_ADDR}/v1/sys/mounts/secret
}

register_plugin() {
  if [ "${PLUGIN_PATH}" != "/vault/plugins" ]; then
    mkdir -p ${PLUGIN_PATH}
    echo "[PLUGIN] Copying plugin to expected folder"
    cp $PLUGIN_FILE "${PLUGIN_PATH}/quorum-hashicorp-vault-plugin"
  fi

  echo "[PLUGIN] Registering Quorum Hashicorp Vault plugin..."
  SHA256SUM=$(sha256sum -b ${PLUGIN_FILE} | cut -d' ' -f1)

  curl -k -s --cacert $VAULT_CA_CERT --header "X-Vault-Token: ${VAULT_TOKEN}" --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data "{\"sha256\": \"${SHA256SUM}\", \"command\": \"quorum-hashicorp-vault-plugin\" }" \
    ${VAULT_ADDR}/v1/sys/plugins/catalog/secret/quorum-hashicorp-vault-plugin
}

enable_plugin() {
  echo "[PLUGIN] Enabling Quorum Hashicorp Vault engine..."
  curl -k -s --cacert $VAULT_CA_CERT --header "X-Vault-Token: ${VAULT_TOKEN}" --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"type": "plugin", "plugin_name": "quorum-hashicorp-vault-plugin", "config": {"force_no_cache": true, "passthrough_request_headers": ["X-Vault-Namespace"]} }' \
    ${VAULT_ADDR}/v1/sys/mounts/quorum

  if [ -n "$VAULT_TOKEN" ]; then
    echo "[PLUGIN] Root token saved in ${VAULT_TOKEN_PATH}"
    mkdir -p ${VAULT_TOKEN_PATH}
    echo "$VAULT_TOKEN" >${VAULT_TOKEN_PATH}/${VAULT_TOKEN_FILE_NAME}
  fi
}

creat_plugin_policies() {
  echo "[PLUGIN] Creating policies over quorum path..."
  curl \
    -k -s --header "X-Vault-Token: ${VAULT_TOKEN}" --request --cacert $VAULT_CACERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"policy":"path \"secret/quorum/*\" {capabilities = [\"list\",\"create\", \"update\", \"read\", \"delete\"]}"}' \
    ${VAULT_ADDR}/v1/sys/policy/quorum

  echo "[PLUGIN] Creating auth token for QKM..."
  curl -k -s --header "X-Vault-Token: ${VAULT_TOKEN}" --request --cacert $VAULT_CACERT --request POST \
    --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY \
    --data '{"policy": "quorum"}' ${VAULT_ADDR}/v1/auth/token/create >response.json

  QKM_TOKEN=$(cat response.json | jq .auth | jq .client_token | tr -d '"')
  echo QKM_TOKEN: $QKM_TOKEN

  rm response.json

  if [ -n "$QKM_TOKEN" ]; then
    echo "[PLUGIN] QKM token saved in ${QKM_TOKEN_PATH}"
    mkdir -p ${QKM_TOKEN_PATH}
    echo "$QKM_TOKEN" >${QKM_TOKEN_PATH}/${QKM_TOKEN_FILE_NAME}
  fi
}

echo "[Vault Server] Initializing Vault: ${VAULT_ADDR}"
init_vault

echo "[Vault Server] Unsealing vault..."
unseal_vault

echo "[Vault Server] Enable KV2 Key engine"
enable_kv2_key_engine

echo "[Vault Server] Register Quorum Plugin"
register_plugin

echo "[Vault Server] Enable Quorum Plugin"
enable_plugin

echo "[Vault Server] Create Policies over Quorum mount path"
creat_plugin_policies

exit 0
