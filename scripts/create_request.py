from web3 import Web3
import json
import time

# Configuration
arbitrum_sepolia_rpc_url = "https://sepolia-rollup.arbitrum.io/rpc"

# Private keys for your accounts
metamask_private_keys = [
    "2ae27eeaa8095f56cd7c02adddd144bdc02d67c3d2a890b7f2ee0097cd520934"  # Private key for 0xA10A627707da9278f07C80983696Dc153E4714aE
]

# Load ABIs from files
with open('ComputationMarketABI.json', 'r') as abi_file:
    market_contract_abi = json.load(abi_file)

with open("COMPToken.json", 'r') as f:
    comp_token_abi = json.load(f)

# Connect to Arbitrum Sepolia
web3 = Web3(Web3.HTTPProvider(arbitrum_sepolia_rpc_url))
assert web3.is_connected(), "Failed to connect to Arbitrum Sepolia"

# Load contract addresses
market_contract_address = "0x20Cb5CfC1c68695778384185540b100689064d05"
comp_token_contract_address = "0x01778E1F4c04dC85049459d311B2091f58539ff1"

# Create contract instances
market_contract = web3.eth.contract(address=market_contract_address, abi=market_contract_abi)
comp_token_contract = web3.eth.contract(address=comp_token_contract_address, abi=comp_token_abi)

def approve(comp_token_contract, spender_address, amount, account, private_key):
    nonce = web3.eth.get_transaction_count(account)
    tx = comp_token_contract.functions.approve(spender_address, amount).build_transaction({
        'from': account,
        'nonce': nonce,
        'gas': 2000000,
        'gasPrice': web3.to_wei('5', 'gwei')
    })
    signed_tx = web3.eth.account.sign_transaction(tx, private_key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Approve transaction receipt: {receipt}")

def create_request(market_contract, account, private_key):
    paymentForProvider = 100 * 10**18
    paymentPerRoundForVerifiers = 10 * 10**18
    numOperations = 6000
    numVerifiers = 5
    inputFileURLs = ["https://example.com/input1", "https://example.com/input2"]
    operationFileURL = "https://example.com/operations"
    computationDeadline = 1722798198
    verificationDeadline = 1822798198
    timeAllocatedForVerification = 60
    numVerifiersSampleSize = 3
    protocolVersion = 1
    layerSize = 2500
    hashOfInputFiles = web3.keccak(text="example hash")  # Placeholder value
    stake = 500 * 10**18

    tx = market_contract.functions.createRequest(
        paymentForProvider,
        paymentPerRoundForVerifiers,
        numOperations,
        numVerifiers,
        inputFileURLs,
        operationFileURL,
        computationDeadline,
        verificationDeadline,
        timeAllocatedForVerification,
        numVerifiersSampleSize,
        protocolVersion,
        layerSize,
        hashOfInputFiles,
        stake
    ).build_transaction({
        'from': account,
        'nonce': web3.eth.get_transaction_count(account),
        'gas': 2000000,
        'gasPrice': web3.to_wei('5', 'gwei')
    })
    
    signed_tx = web3.eth.account.sign_transaction(tx, private_key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Request created: {web3.to_hex(tx_hash)}")
    print(f"Transaction receipt: {receipt}")

# Main function
if __name__ == "__main__":
    consumer_account = web3.eth.account.from_key(metamask_private_keys[0])
    consumer_address = consumer_account.address
    consumer_private_key = metamask_private_keys[0]

    approve(comp_token_contract, market_contract_address, 500 * 10**18, consumer_address, consumer_private_key)
    create_request(market_contract, consumer_address, consumer_private_key)

# Function to select a request as provider with actual parameters
#def select_request(provider_account, private_key, request_id):
#    tx = contract.functions.selectRequest(request_id).build_transaction({
#        'from': provider_account,
#        'nonce': web3.eth.get_transaction_count(provider_account),
#        'gas': 2000000,
#        'gasPrice': web3.to_wei('5', 'gwei')
#    })
#    
#    signed_tx = web3.eth.account.sign_transaction(tx, private_key)
#    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
#    web3.eth.wait_for_transaction_receipt(tx_hash)
#    print(f"Request selected by provider: {web3.to_hex(tx_hash)}")

# Function to listen for RequestCreated events
#def listen_for_request_created():
#    event_filter = contract.events.RequestCreated.create_filter(fromBlock='latest')
#    while True:
#        for event in event_filter.get_new_entries():
#            print(f"Request Created: {event['args']['requestId']} by {event['args']['consumer']}")
#        time.sleep(5)