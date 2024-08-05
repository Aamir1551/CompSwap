from web3 import Web3
import json
import time
from datetime import datetime, timedelta
from web3.exceptions import ContractLogicError
import eth_abi
import random
import solcx

solcx.install_solc('0.8.25')
solcx.set_solc_version('0.8.25')

def get_abi_market(file_path, contract_name):
    # Compile the contract
    with open(file_path, 'r') as file:
        contract_source_code = file.read()

    import_remappings = {
        "@openzeppelin/": "../node_modules/@openzeppelin/"
    }

    compiled_sol = solcx.compile_source(contract_source_code, output_values=['abi', 'bin'],
                                        import_remappings=import_remappings,
                                        optimize=True,
                                        via_ir=True)

    # Extract ABI and bytecode
    contract_interface = compiled_sol['<stdin>:' + contract_name]
    abi = contract_interface['abi']
    bytecode = contract_interface['bin']
    return bytecode, abi

def build_and_send_tx(func, account, private_key, gas=2000000, gas_price='5', is_constructor=False):
    if is_constructor:
        tx = func
    else:
        tx = func.build_transaction({
            'from': account.address,
            'nonce': web3.eth.get_transaction_count(account.address),
            'gas': gas,
            'gasPrice': web3.to_wei(gas_price, 'gwei')
        })
    
    signed_tx = web3.eth.account.sign_transaction(tx, private_key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    time.sleep(4)  # Wait for transaction to be mined
    return web3.eth.get_transaction_receipt(tx_hash)

# Configuration
arbitrum_sepolia_rpc_url = "https://sepolia-rollup.arbitrum.io/rpc"
#market_contract_address = "0x178Ad076e22C19bFd814B35A9E4ebb5eb13f34b4"
#comp_token_contract_address = "0x5d9aD2c556f2C50Ba1ce346bc2b7741c6387d055"

#ganache_rpc_url = "HTTP://127.0.0.1:7545"  # URL for local Ganache instance
#web3 = Web3(Web3.HTTPProvider(ganache_rpc_url))
#assert web3.is_connected(), "Failed to connect to Ganache"

# Connect to Arbitrum Sepolia
web3 = Web3(Web3.HTTPProvider(arbitrum_sepolia_rpc_url))
assert web3.is_connected(), "Failed to connect to Arbitrum Sepolia"

(bytecode_market, market_contract_abi) = get_abi_market("../contracts/ComputationMarket.sol", "ComputationMarket")
market_contract = web3.eth.contract(bytecode=bytecode_market, abi=market_contract_abi)

(bytecode_token, comp_token_abi) = get_abi_market("../contracts/COMPToken.sol", "COMPToken")
comp_contract = web3.eth.contract(bytecode=bytecode_token, abi=comp_token_abi)

deployerPrivateKey = "2ae27eeaa8095f56cd7c02adddd144bdc02d67c3d2a890b7f2ee0097cd520934"
deployer = web3.eth.account.from_key(deployerPrivateKey)
deployer_address = deployer.address

# Check deployer's balance
print("Deployers Address: ", deployer_address)
deployer_balance = web3.eth.get_balance(deployer_address)
print(f"Deployer balance: {web3.from_wei(deployer_balance, 'ether')} ETH")

tx = comp_contract.constructor(1000000 * 10 ** 18).build_transaction({
    'from': deployer_address,
    'nonce': web3.eth.get_transaction_count(deployer_address),
    'gas': 10100000,
    'gasPrice': web3.to_wei('5', 'gwei')
})
comp_token_contract_address = build_and_send_tx(tx, deployer, deployerPrivateKey, is_constructor=True).contractAddress
print("Comp token address: ", comp_token_contract_address)

tx = market_contract.constructor(comp_token_contract_address).build_transaction({
    'from': deployer_address,
    'nonce': web3.eth.get_transaction_count(deployer_address),
    'gas': 14479671,
    'gasPrice': web3.to_wei('5', 'gwei')
})
market_contract_address = build_and_send_tx(tx, deployer, deployerPrivateKey, is_constructor=True).contractAddress
print("Market address: ", market_contract_address)

with open('./../ComputationMarketABI.json', 'w') as file:
    file.write(json.dumps(market_contract_abi))

with open('./../COMPToken.json', 'w') as file:
    file.write(json.dumps(comp_token_abi))

with open('./../private_keys.json', 'r') as file:
    keys = json.load(file)

time.sleep(2)

metamask_private_keys = [
    keys["consumer"],  # Consumer
    keys["provider"],  # Provider
    keys["verifier1"],  # Verifier1
    keys["verifier2"],  # Verifier2
    keys["verifier3"],  # Verifier3
    keys["verifier4"],  # Verifier4
    keys["verifier5"]   # Verifier5
]

account_roles = [
    "Consumer",
    "Provider",
    "Verifier1",
    "Verifier2",
    "Verifier3",
    "Verifier4",
    "Verifier5"
]

# Load ABIs from files
#with open('ComputationMarketABI.json', 'r') as abi_file:
#    market_contract_abi = json.load(abi_file)

#with open("COMPToken.json", 'r') as f:
#    comp_token_abi = json.load(f)



# Create contract instances
market_contract = web3.eth.contract(address=market_contract_address, abi=market_contract_abi)
comp_token_contract = web3.eth.contract(address=comp_token_contract_address, abi=comp_token_abi)

def get_balance(account):
    balance = comp_token_contract.functions.balanceOf(account.address).call()
    return web3.from_wei(balance, 'ether')

def print_balance(accounts, roles):
    for account, role in zip(accounts, roles):
        print(f"Balance of {account.address} ({role}): {get_balance(account)} COMPToken")


def approve_tokens(spender_address, amount, account, private_key):
    func = comp_token_contract.functions.approve(spender_address, amount)
    receipt = build_and_send_tx(func, account, private_key)
    print(f"{account.address} approved {amount} tokens for {spender_address}")

def transfer_tokens(to_account, amount, from_account, private_key):
    func = comp_token_contract.functions.transfer(to_account.address, amount)
    receipt = build_and_send_tx(func, from_account, private_key)
    print(f"Transferred {amount} tokens from {from_account.address} to {to_account.address}")

def create_request(account, private_key):
    func = market_contract.functions.createRequest(
        100 * 10**18,
        10 * 10**18,
        6000,
        5,
        ["https://example.com/input1", "https://example.com/input2"],
        "https://example.com/operations",
        int((datetime.now() + timedelta(hours=1)).timestamp()),
        int((datetime.now() + timedelta(hours=2)).timestamp()),
        20,
        3,
        1,
        2500,
        web3.keccak(text="example hash"),
        500 * 10**18
    )
    receipt = build_and_send_tx(func, account, private_key)
    time.sleep(5)
    request_id = market_contract.functions.requestCount().call() - 1
    print(f"Request created with ID: {request_id} by Consumer")
    print_balance([account], ["Consumer"])
    return request_id

def select_request(provider_account, private_key, request_id):
    func = market_contract.functions.selectRequest(request_id)
    receipt = build_and_send_tx(func, provider_account, private_key)
    print(f"Request {request_id} selected by Provider")
    print_balance([provider_account], ["Provider"])

def complete_request(provider_account, private_key, request_id, outputFileURLs):
    func = market_contract.functions.completeRequest(request_id, outputFileURLs)
    receipt = build_and_send_tx(func, provider_account, private_key)
    print(f"Request {request_id} completed by Provider")

def apply_for_verification(verifier_account, private_key, request_id):
    func = market_contract.functions.applyForVerificationForRequest(request_id)
    receipt = build_and_send_tx(func, verifier_account, private_key)
    print(f"Verifier {verifier_account.address} applied for verification")
    print_balance([verifier_account], ["Verifier"])

def trigger_verifier(verifier_account, private_key, request_id):
    func = market_contract.functions.chooseVerifiersForRequestTrigger(request_id)
    receipt = build_and_send_tx(func, verifier_account, private_key)
    print(f"Verifier {verifier_account.address} triggered verifier selection")

def submit_commitment(verifier_account, private_key, request_id, computed_hash):
    func = market_contract.functions.submitCommitment(request_id, computed_hash)
    receipt = build_and_send_tx(func, verifier_account, private_key)
    print(f"Verifier {verifier_account.address} submitted commitment")

def reveal_provider_key_and_hash(provider_account, private_key, request_id, answerHash, privateKeyRand, initialisationVecRand):
    func = market_contract.functions.revealProviderKeyAndHash(
        request_id,
        privateKeyRand,
        initialisationVecRand,
        answerHash 
    )
    receipt = build_and_send_tx(func, provider_account, private_key)
    print(f"Provider revealed key and hash for request {request_id}")


# add a bunch of stupid emit statements to figure out where it's failing
# also write out the rest of the functions in a better way. maybe make a owner contract, and a sepearte contract to act as a consumer
def reveal_commitment(verifier_account, private_key, request_id, agree, answerHash, nonce):
    try:
        func = market_contract.functions.revealCommitment(
            request_id,
            agree,
            answerHash,
            nonce 
        )
        tx = func.build_transaction({
            'from': verifier_account.address,
            'nonce': web3.eth.get_transaction_count(verifier_account.address),
            'gas': 2000000,
            'gasPrice': web3.to_wei('5', 'gwei')
        })
        signed_tx = web3.eth.account.sign_transaction(tx, private_key)
        tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
        
        print(f"Transaction hash: {web3.to_hex(tx_hash)}")

        receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
        
        if receipt['status'] == 1:
            print(f"Verifier {verifier_account.address} revealed commitment successfully")
        else:
            print(f"Transaction failed with status {receipt['status']}. Transaction hash: {web3.to_hex(tx_hash)}")

            # Attempt to decode the revert reason using debug_traceTransaction
            try:
                trace = web3.manager.request_blocking('debug_traceTransaction', [web3.to_hex(tx_hash), {'disableMemory': True, 'disableStorage': True, 'disableStack': False}])
                if 'error' in trace:
                    revert_reason = trace['error']['message']
                    print(f"Revert reason: {revert_reason}")
                else:
                    print("No revert reason found in the transaction trace.")
            except Exception as decode_error:
                print(f"Failed to trace transaction: {decode_error}")

    except ContractLogicError as e:
        print(f"Transaction reverted with error: {str(e)}")

def calculate_majority_and_reward(verifierAccount, private_key, request_id, round_num):
    func = market_contract.functions.calculateMajorityAndReward(request_id, round_num)
    receipt = build_and_send_tx(func, verifierAccount, private_key)
    print(f"Verifier {verifierAccount.address} calculated majority and reward for {request_id}, round {round_num}")
    print_balance([verifier_account], ["Verifier"])

# Main function
if __name__ == "__main__":
    consumer_account = web3.eth.account.from_key(metamask_private_keys[0])
    provider_account = web3.eth.account.from_key(metamask_private_keys[1])
    verifier_accounts = [web3.eth.account.from_key(key) for key in metamask_private_keys[2:]]

    all_accounts = [consumer_account, provider_account] + verifier_accounts

    #reveal_commitment(verifier_accounts[0], verifier_accounts[00].key, 0, True, web3.keccak(text="hashed_answer"), web3.keccak(text="nonce_0"))

    print_balance(all_accounts, ["Consumer", "Provider", "Verifier1", "Verifier2", "Verifier3", "Verifier4", "Verifier5"])

    # Approve tokens for consumer
    approve_tokens(market_contract_address, 500 * 10**18, consumer_account, consumer_account.key)

    # Transfer tokens to provider and verifiers
    transfer_tokens(provider_account, 1000 * 10**18, consumer_account, consumer_account.key)
    for verifier_account in verifier_accounts:
        transfer_tokens(verifier_account, 500 * 10**18, consumer_account, consumer_account.key)

    print_balance(all_accounts, ["Consumer", "Provider", "Verifier1", "Verifier2", "Verifier3", "Verifier4", "Verifier5"])

    time.sleep(4)
    # Create request
    request_id = create_request(consumer_account, consumer_account.key)

    # Approve tokens for provider to stake
    approve_tokens(market_contract_address, 500 * 10**18, provider_account, provider_account.key)

    # Select request as provider
    select_request(provider_account, provider_account.key, request_id)

    # Complete request as provider (after the first round)
    outputFileURLs = ["https://example.com/output"]
    complete_request(provider_account, provider_account.key, request_id, outputFileURLs)
    time.sleep(6)

    for round_number in range(3):
        print(f"Starting round {round_number + 1}")

        # Apply for verification as verifiers
        for verifier_account in verifier_accounts:
            approve_tokens(market_contract_address, 500 * 10**18, verifier_account, verifier_account.key)
            apply_for_verification(verifier_account, verifier_account.key, request_id)
        time.sleep(6)
        
        for verifier_account in verifier_accounts:
            trigger_verifier(verifier_account, verifier_account.key, request_id)
        time.sleep(6)

        # Submit commitments
        answerHash = web3.keccak(text="hashed_answer")
        for verifier_account in verifier_accounts:
            nonce = web3.keccak(text=f"nonce_{verifier_account.address}")
            computed_hash = web3.keccak(text=f"{answerHash}{nonce}{verifier_account.address}")
            submit_commitment(verifier_account, verifier_account.key, request_id, computed_hash)
        time.sleep(6)

        provider_key = random.randint(0, 10000)
        initialisationVector = random.randint(0, 10000)
        reveal_provider_key_and_hash(provider_account, provider_account.key, request_id, answerHash, provider_key, initialisationVector)
        time.sleep(6)

        # Reveal commitments
        for verifier_account in verifier_accounts:
            nonce = web3.keccak(text=f"nonce_{verifier_account.address}")
            reveal_commitment(verifier_account, verifier_account.key, request_id, True, answerHash, nonce)
        time.sleep(6)

        # Calculate majority and reward
        for verifier_account in verifier_accounts:
            calculate_majority_and_reward(verifier_account, verifier_account.key, request_id, round_number + 1)

        # Print balances at the end of each round
        print(f"Balances after round {round_number + 1}:")
        print_balance(all_accounts, ["Consumer", "Provider", "Verifier1", "Verifier2", "Verifier3", "Verifier4", "Verifier5"])

    print("All rounds completed")
    print_balance(all_accounts, ["Consumer", "Provider", "Verifier1", "Verifier2", "Verifier3", "Verifier4", "Verifier5"])