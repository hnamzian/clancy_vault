ENV_DIR=./dev/test/.env

load_dotenv() {
  if [ -f $ENV_DIR ]; then
    export $(cat $ENV_DIR | sed 's/#.*//g' | xargs)
  fi
}

list_accounts() {
  curl -k --request GET \
    $QKMS_ADDR/stores/eth-accounts/ethereum
}

import_account() {
  PRIV_KEY=$1
  KEY_ID=$2

  curl -k --request POST \
    -d '{ "keyId": "'$KEY_ID'", "privateKey": "'$PRIV_KEY'", "tags": { "property1": "string", "property2": "string" } }' \
    $QKMS_ADDR/stores/eth-accounts/ethereum/import
}

send_eth_transaction() {
  curl -k --request POST \
    $QKMS_ADDR/nodes/mumbai \
    -d '{
      "jsonrpc":"2.0",
      "method":"eth_sendTransaction",
      "params":[
        {
          "from": "'$WALLET_ADDR'",
          "to": "0xbAD64d41438D5E72c11923E842C5618bAa86e73E",
          "data": "0x6057361d0000000000000000000000000000000000000000000000000000000000000001",
          "gasPrice": "0x1944883241",
          "value": "0x0"
        }
      ],
      "id":1
    }'
}

echo [TEST] "Load Environment Variables"
load_dotenv

echo [TEST] "List Initial Accounts"
list_accounts

echo [TEST] "Import Private Key"
import_account $PRIVATE_KEY $KEY_ID

echo [TEST] "List Accounts after imports"
list_accounts

echo [TEST] "Send Transaction to Mumbai network"
send_eth_transaction