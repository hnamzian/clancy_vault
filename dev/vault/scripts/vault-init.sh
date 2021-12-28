VAULT_ADDR=${VAULT_ADDR-localhost:8200}
PLUGIN_MOUNT_PATH=${PLUGIN_MOUNT_PATH-quorum}
ROOT_TOKEN_PATH=${ROOT_TOKEN_PATH-./dev/vault/token}
ROOT_TOKEN_FILE_NAME=${ROOT_TOKEN_FILE_NAME-root}
UNSEAL_KEYS_PATH=${UNSEAL_KEYS_PATH-./dev/vault/unseal}
UNSEAL_KEYS_FILE_NAME=${UNSEAL_KEYS_FILE_NAME-unseal_keys}
QKM_TOKEN_PATH=${QKM_TOKEN_PATH-./dev/vault/token}
QKM_TOKEN_FILE_NAME=${QKM_TOKEN_FILE_NAME-qkm_token}
PLUGIN_FILE=./vault-plugins/quorum-hashicorp-vault-plugin

echo "[PLUGIN] Initializing Vault: ${VAULT_ADDR}"

curl -s --request POST --data '{"secret_shares": 7, "secret_threshold": 4}' ${VAULT_ADDR}/v1/sys/init > response.json

ROOT_TOKEN=$(cat response.json | jq .root_token | tr -d '"')
UNSEAL_KEYS=$(cat response.json | jq .keys )
UNSEAL_KEY_0=$(cat response.json | jq .keys | jq '.[0]')
UNSEAL_KEY_1=$(cat response.json | jq .keys | jq '.[1]')
UNSEAL_KEY_2=$(cat response.json | jq .keys | jq '.[2]')
UNSEAL_KEY_3=$(cat response.json | jq .keys | jq '.[3]')
UNSEAL_KEY_4=$(cat response.json | jq .keys | jq '.[4]')
UNSEAL_KEY_5=$(cat response.json | jq .keys | jq '.[5]')
UNSEAL_KEY_6=$(cat response.json | jq .keys | jq '.[6]')
ERRORS=$(cat response.json | jq .errors | jq '.[0]')
rm response.json

echo ROOT_TOKEN: $ROOT_TOKEN
echo UNSEAL_KEYS: $UNSEAL_KEYS

if [ "$UNSEAL_KEYS" = "null" ]; then
  echo "[PLUGIN] cannot retrieve unseal key: $ERRORS"
  exit 1
fi

if [ -n "$UNSEAL_KEYS" ]; then 
  echo "[PLUGIN] Unseal_Keys saved in ${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}"
  mkdir -p ${UNSEAL_KEYS_PATH}
  echo "$UNSEAL_KEYS" > ${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}
fi

# Unseal Vault
echo "[PLUGIN] Unsealing vault..."
curl -s --request POST --data '{"key": '${UNSEAL_KEY_0}'}' ${VAULT_ADDR}/v1/sys/unseal
curl -s --request POST --data '{"key": '${UNSEAL_KEY_1}'}' ${VAULT_ADDR}/v1/sys/unseal
curl -s --request POST --data '{"key": '${UNSEAL_KEY_2}'}' ${VAULT_ADDR}/v1/sys/unseal
curl -s --request POST --data '{"key": '${UNSEAL_KEY_3}'}' ${VAULT_ADDR}/v1/sys/unseal

echo "[PLUGIN] Registering Quorum Hashicorp Vault plugin..."
SHA256SUM=$(sha256sum -b ${PLUGIN_FILE} | cut -d' ' -f1)
curl -s --header "X-Vault-Token: ${ROOT_TOKEN}" --request POST \
  --data "{\"sha256\": \"${SHA256SUM}\", \"command\": \"quorum-hashicorp-vault-plugin\" }" \
  ${VAULT_ADDR}/v1/sys/plugins/catalog/secret/quorum-hashicorp-vault-plugin

echo "[PLUGIN] Enabling Quorum Hashicorp Vault engine..."
curl -s --header "X-Vault-Token: ${ROOT_TOKEN}" --request POST \
  --data '{"type": "plugin", "plugin_name": "quorum-hashicorp-vault-plugin", "config": {"force_no_cache": true, "passthrough_request_headers": ["X-Vault-Namespace"]} }' \
  ${VAULT_ADDR}/v1/sys/mounts/${PLUGIN_MOUNT_PATH}

if [ -n "$ROOT_TOKEN" ]; then 
  echo "[PLUGIN] Root token saved in ${ROOT_TOKEN_PATH}"
  mkdir -p ${ROOT_TOKEN_PATH}
  echo "$ROOT_TOKEN" > ${ROOT_TOKEN_PATH}/${ROOT_TOKEN_FILE_NAME}
fi

echo "[PLUGIN] Creating policies over quorum path..."
curl \
  --request POST \
  --header "X-Vault-Token: ${ROOT_TOKEN}" \
  --data '{"policy":"path \"secret/quorum/*\" {capabilities = [\"list\",\"create\", \"update\", \"read\", \"delete\"]}"}' \
  ${VAULT_ADDR}/v1/sys/policy/quorum

echo "[PLUGIN] Creating auth token for QKM..."
curl -s --request POST --header "X-Vault-Token: ${ROOT_TOKEN}" --data '{"policy": "quorum"}' ${VAULT_ADDR}/v1/auth/token/create > response.json

QKM_TOKEN=$(cat response.json | jq .auth | jq .client_token | tr -d '"')
echo QKM_TOKEN: $QKM_TOKEN

rm response.json

if [ -n "$QKM_TOKEN" ]; then 
  echo "[PLUGIN] QKM token saved in ${QKM_TOKEN_PATH}"
  mkdir -p ${QKM_TOKEN_PATH}
  echo "$QKM_TOKEN" > ${QKM_TOKEN_PATH}/${QKM_TOKEN_FILE_NAME}
fi

exit 0
