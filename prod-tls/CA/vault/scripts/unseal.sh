VAULT_ADDR=${VAULT_ADDR-localhost:7200}
ROOT_TOKEN_PATH=${VAULT_CA_ROOT_TOKEN_PATH-./CA/vault/token}
ROOT_TOKEN_FILE_NAME=${VAULT_CA_ROOT_TOKEN_FILE_NAME-root}
UNSEAL_KEYS_PATH=${UNSEAL_KEYS_PATH-./CA/vault/unseal}
UNSEAL_KEYS_FILE_NAME=${UNSEAL_KEYS_FILE_NAME-unseal_keys}

init_vault() {
  curl -s --request POST \
    --data '{"secret_shares": 7, "secret_threshold": 4}' \
    ${VAULT_ADDR}/v1/sys/init >response.json

  ROOT_TOKEN=$(cat response.json | jq .root_token | tr -d '"')
  UNSEAL_KEYS=$(cat response.json | jq .keys)
  UNSEAL_KEY_0=$(cat response.json | jq .keys | jq '.[0]')
  UNSEAL_KEY_1=$(cat response.json | jq .keys | jq '.[1]')
  UNSEAL_KEY_2=$(cat response.json | jq .keys | jq '.[2]')
  UNSEAL_KEY_3=$(cat response.json | jq .keys | jq '.[3]')

  ERRORS=$(cat response.json | jq .errors | jq '.[0]')
  if [ "$UNSEAL_KEYS" = "null" ]; then
    echo "[Vault CA] cannot retrieve unseal key: $ERRORS"
    exit 1
  fi

  if [ -n "$ROOT_TOKEN" ]; then
    echo "[Vault CA] Root token saved in ${ROOT_TOKEN_PATH}"
    mkdir -p ${ROOT_TOKEN_PATH}
    echo "$ROOT_TOKEN" >${ROOT_TOKEN_PATH}/${ROOT_TOKEN_FILE_NAME}
  fi

  if [ -n "$UNSEAL_KEYS" ]; then
    echo "[Vault CA] Unseal_Keys saved in ${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}"
    mkdir -p ${UNSEAL_KEYS_PATH}
    echo "$UNSEAL_KEYS" >${UNSEAL_KEYS_PATH}/${UNSEAL_KEYS_FILE_NAME}
  fi

  rm response.json
}

unseal_vault() {
  curl -s --request POST --data '{"key": '${UNSEAL_KEY_0}'}' ${VAULT_ADDR}/v1/sys/unseal
  curl -s --request POST --data '{"key": '${UNSEAL_KEY_1}'}' ${VAULT_ADDR}/v1/sys/unseal
  curl -s --request POST --data '{"key": '${UNSEAL_KEY_2}'}' ${VAULT_ADDR}/v1/sys/unseal
  curl -s --request POST --data '{"key": '${UNSEAL_KEY_3}'}' ${VAULT_ADDR}/v1/sys/unseal
}

echo "[Vault CA] Initializing Vault: ${VAULT_ADDR}"
init_vault

echo "[Vault CA] Unsealing Vault CA"
unseal_vault
