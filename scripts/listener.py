from web3 import Web3
import json
import time

# Configuration
arbitrum_sepolia_rpc_url = "https://sepolia-rollup.arbitrum.io/rpc"
market_contract_address = "0xa277497b26Fc332b430bF9ED50b8BD52FE77376A"

# Load ABI from file
with open('../ComputationMarketABI.json', 'r') as abi_file:
    market_contract_abi = json.load(abi_file)

# Connect to Arbitrum Sepolia
web3 = Web3(Web3.HTTPProvider(arbitrum_sepolia_rpc_url))
assert web3.is_connected(), "Failed to connect to Arbitrum Sepolia"

# Create contract instance
market_contract = web3.eth.contract(address=market_contract_address, abi=market_contract_abi)

def handle_alert_verifiers(event):
    print(f"AlertVerifiers event received: requestId={event['args']['requestId']}, provider={event['args']['provider']}, verificationPrice={event['args']['verificationPrice']}, verificationDeadline={event['args']['verificationDeadline']}, timeAllocatedForVerification={event['args']['timeAllocatedForVerification']}")

def handle_verification_applied(event):
    print(f"VerificationApplied event received: requestId={event['args']['requestId']}, verifier={event['args']['verifier']}, layerComputeIndex={event['args']['layerComputeIndex']}")

def handle_reveal_verification_details(event):
    print(f"RevealVerificationDetails event received: requestId={event['args']['requestId']}, endTime={event['args']['endTime']}, verifier={event['args']['verifier']}")

def handle_provider_unsuccessful(event):
    print(f"ProviderResultUnsuccessful event received: requestId={event['args']['requestId']}")

def handle_provider_successful(event):
    print(f"ProviderResultSuccessfullyVerified event received: requestId={event['args']['requestId']}")

def handle_reveal_commitment_failed(event):
    print(f"RevealCommitmentFailed event received: requestId={event['args']['requestId']} newHashComputed={event['args']['newHashComputed']} oldHashComputed={event['args']['oldHashComputed']}")

def listen_to_events():
    latest_block = web3.eth.block_number

    while True:
        try:
            new_block = web3.eth.block_number

            if new_block > latest_block:
                alert_verifiers_events = market_contract.events.AlertVerifiers().get_logs(fromBlock=latest_block + 1, toBlock=new_block)
                verification_applied_events = market_contract.events.VerificationApplied().get_logs(fromBlock=latest_block + 1, toBlock=new_block)
                reveal_verification_details_events = market_contract.events.RevealVerificationDetails().get_logs(fromBlock=latest_block + 1, toBlock=new_block)

                provider_unsuccessful_events = market_contract.events.ProviderResultUnsuccessful().get_logs(fromBlock=latest_block + 1, toBlock=new_block)
                provider_successful_events = market_contract.events.ProviderResultSuccessfullyVerified().get_logs(fromBlock=latest_block + 1, toBlock=new_block)

                reveal_commitment_events = market_contract.events.RevealCommitmentFailed().get_logs(fromBlock=latest_block + 1, toBlock=new_block)

                for event in alert_verifiers_events:
                    handle_alert_verifiers(event)

                for event in verification_applied_events:
                    handle_verification_applied(event)

                for event in reveal_verification_details_events:
                    handle_reveal_verification_details(event)

                for event in provider_unsuccessful_events:
                    handle_provider_unsuccessful(event)
                
                for event in provider_successful_events:
                    handle_provider_successful(event)

                for event in reveal_commitment_events:
                    handle_reveal_commitment_failed(event)

                latest_block = new_block

            time.sleep(1)
        except Exception as e:
            print(f"An error occurred: {str(e)}")
            time.sleep(1)

if __name__ == "__main__":
    listen_to_events()