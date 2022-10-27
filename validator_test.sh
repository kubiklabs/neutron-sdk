args=("$@")

BIN=neutrond
CONTRACT=${args[0]}
CONNECTION_ID=${args[1]}

NEUTRON_KEY_NAME=validator_test
INTERCHAIN_ACCOUNT_ID=version1
GAS_PRICES=0.01untrn
TARGET_VALIDATOR=junovaloper18wgy6hy6yv3fvevl5pyfn7cvzx3t5use2vssnf
TARGET_DENOM=ujunox
EXPLORER_URL=http://23.109.159.28:3333/
FAUCET_URL=http://23.109.159.28/
NEUTRON_NODE_ADDRESS=127.0.0.1

if [ $# != "2" ]
then
    echo "Usage: ./validator_test.sh [path_to_wasm_artifact] [connection-id]"
    exit
fi

if [[ ! -f $CONTRACT ]]
then
    echo "Artifact file doesn't exists"
    exit
fi

if ! command -v $BIN &> /dev/null
then
    echo "$BIN could not be found.
You can add symlink from your neutron binary to /bin this way: ln -s PATH_TO_NEUTRON_BIN /bin/neutron"
    exit
fi

NEUTRON_CHAIN_ID=$(neutrond status | jq -r '.NodeInfo.network')

if [ -z "$NEUTRON_CHAIN_ID" ]
then
    echo "Cannot get chain id"
    exit;
fi
echo "Chain id: $NEUTRON_CHAIN_ID"

RES=$(neutrond query ibc connection end $CONNECTION_ID 2>/dev/null)

if [ -z "$RES" ]
then
    echo "No such open connection for provided connection-id"
    exit;
fi
echo "Connection id: $CONNECTION_ID"
echo ""


RES=$($BIN keys add $NEUTRON_KEY_NAME --output json)
NEUTRON_ADDRESS=$(echo $RES | jq -r .address)
MNEMONIC=$(echo $RES | jq -r .mnemonic)
if [ $NEUTRON_ADDRESS = "null" ]
then
    echo "Can't get address from key"
    exit
fi

echo "Local address in neutron: $NEUTRON_ADDRESS"
echo "Key mnemonic: $MNEMONIC"
echo "Key name: $NEUTRON_KEY_NAME"
echo ""
echo "Please go to $FAUCET_URL and get tokens for $NEUTRON_ADDRESS"
echo "Make sure tx is passed by going to $EXPLORER_URL/accounts/$NEUTRON_ADDRESS"
echo "Hit enter when ready"
read
echo "Upload the queries contract"
RES=$(${BIN} tx wasm store ${CONTRACT} --from ${NEUTRON_KEY_NAME} --gas 50000000 --chain-id ${NEUTRON_CHAIN_ID} --broadcast-mode=block --gas-prices ${GAS_PRICES}  -y --output json)
CONTRACT_CODE_ID=$(echo $RES | jq -r '.logs[0].events[1].attributes[0].value')
if [ $CONTRACT_CODE_ID = "null" ]
then
    echo "Can't get code id"
    exit
fi

echo "Contract code id: $CONTRACT_CODE_ID"
echo ""
echo "Instantiate the contract"
INIT_CONTRACT='{}'
RES=$(${BIN} tx wasm instantiate $CONTRACT_CODE_ID "$INIT_CONTRACT" --from $NEUTRON_KEY_NAME --admin ${NEUTRON_ADDRESS} -y --chain-id ${NEUTRON_CHAIN_ID} --output json --broadcast-mode=block --label "init"  --gas-prices ${GAS_PRICES} --gas auto --gas-adjustment 1.4)
CONTRACT_ADDRESS=$(echo $RES | jq -r '.logs[0].events[0].attributes[0].value')
echo "Contract address: $CONTRACT_ADDRESS"


if [ $CONTRACT_ADDRESS = "null" ]
then
    echo "Can't get contract address"
    exit
fi

echo ""
echo "Register interchain account"
RES=$(${BIN} tx wasm execute ${CONTRACT_ADDRESS} "{\"register\": {\"connection_id\": \"${CONNECTION_ID}\", \"interchain_account_id\": \"${INTERCHAIN_ACCOUNT_ID}\"}}" --from $NEUTRON_KEY_NAME  -y --chain-id ${NEUTRON_CHAIN_ID} --output json --broadcast-mode=block --gas-prices ${GAS_PRICES} --gas 1000000)
echo "Waiting for registering account..."
sleep 60


RES=$(neutrond query wasm contract-state smart ${CONTRACT_ADDRESS} "{\"interchain_account_address_from_contract\":{\"interchain_account_id\":\"${INTERCHAIN_ACCOUNT_ID}\"}}" --chain-id ${NEUTRON_CHAIN_ID} --output json)
ICA_ADDRESS=$(echo $RES | jq -r '.data | .[0]')
if [ ${#ICA_ADDRESS} != "63" ]
then
    echo "Can't get ICA address"
    exit
fi
echo "ICA address: $ICA_ADDRESS"
echo ""
echo "Please send 0.02 junox to $ICA_ADDRESS You can get use faucet from "
echo "hit enter when you are ready"
read
echo ""
echo "Execute Interchain Delegate tx"
RES=$(${BIN} tx wasm execute ${CONTRACT_ADDRESS} "{\"delegate\": {\"interchain_account_id\": \"${INTERCHAIN_ACCOUNT_ID}\", \"validator\": \"${TARGET_VALIDATOR}\", \"denom\":\"${TARGET_DENOM}\", \"amount\":\"9000\"}}" --from ${NEUTRON_KEY_NAME}  -y --chain-id ${NEUTRON_CHAIN_ID} --output json --broadcast-mode=block --gas-prices ${GAS_PRICES} --gas 1000000)
CODE=$(echo $RES | jq -r '.code')
if [ $CODE != "0" ]
then
    echo "Delegation failed"
fi
echo "Waiting for delegation..."
sleep 30;

echo ""
echo "Checking acknowledgement"
RES=$(${BIN} query wasm contract-state smart ${CONTRACT_ADDRESS} "{\"acknowledgement_result\":{\"interchain_account_id\":\"${INTERCHAIN_ACCOUNT_ID}\", \"sequence_id\": 1}}" --chain-id ${NEUTRON_CHAIN_ID} --output json)
if [ "$RES" != "{\"data\":{\"success\":[\"/cosmos.staking.v1beta1.MsgDelegate\"]}}" ]
then
    echo "Error: Acknowledgement has not been received"
    exit
fi
echo "Acknowledgement has  been received"
echo ""
echo "Now you can check your delegation here https://testnet.juno.explorers.guru/account/$ICA_ADDRESS"
echo "Hit return to exit"
read


