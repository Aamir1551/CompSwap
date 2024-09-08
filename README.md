In this project, we create a computational marketplace on the Ethereum blockchain as per my thesis. The contracts are all deployed on the Arbitrum One chain.

The marketplace is deployed at address: 0xf1d4Ff17b93Ee22A899EBea292fBD69AA621eE0D  
The token (called COMP token) is deployed at address: 0x4bF7a4aba7122EB9cDE8F563a65Bd3B623DAECbF  
The NFT is deployed at address: 0xA84e318a193465b19Df80d21Ef5Efee315065104  
The HandlerFunctionsCompMarket is deployed at address: 0xf8b425579A0F7963a689de91a3a4968Af54425cC  

To view the token on ArbScan: https://arbiscan.io/address/0x4bF7a4aba7122EB9cDE8F563a65Bd3B623DAECbF  
To view the NFT on ArbScan: https://arbiscan.io/address/0xA84e318a193465b19Df80d21Ef5Efee315065104  
To view the Marketplace contract on Arbscan: https://arbiscan.io/address/0xf1d4Ff17b93Ee22A899EBea292fBD69AA621eE0D   

To view our token on Uniswap, see: https://app.uniswap.org/explore/tokens/arbitrum/0x4bf7a4aba7122eb9cde8f563a65bd3b623daecbf  
To buy this token, you will need Eth on Arbitrum Sepolia to swap for the CompToken

You can interact with these contracts using remix: https://remix.ethereum.org/. First compile the contract that you'd like to deploy in remix (copy and paste the appropriate file where the contract is defined into remix), and then click on the "Deploy and run transactions" tab, and write the address that you'd like to interact with in the "Load contract from Address" textbox. After this, click the blue "At Address" box, and remix will now offer you the functions that you can use to interact with this contract.

All contract code lives in the folder: `contracts`. All relevent python files we discuss below also lives in the `contracts` folder.

Note that a single COMP token is equal to 10**18 COMP units, since the COMP token follows the ERC20 standard.

To run the python files (all defined in the `contracts` folder) you will need to create a virtual environment by: 

```
python3 -m venv myenv
source myenv/bin/activate
```
Which will create a virtual environment called myenv (on a linux machine).
After this, please run:
```
pip install -r requirements.txt
```
Which will install the necessary packages you require. After this, run the python files in this virtual environment.
Note that we are using python version 3.12.4

You can run this project, by running the relevant python file: `contracts/AllCorrectSimulator.ipynb` (or run `contracts/Protocol1AllCorrectSimulator.ipynb` to do a run using protocol 1 without any example hashes).
In that file, we do a successful verification run of a request which we also deploy on the Arbiturm sepolia test net.


The files `contracts/ProviderIncorrectSimulator.ipynb` and `contracts/VerifierIncorrectSimulator.ipynb` deploy the necessary contracts for the marketplace on the Arbitrum Sepolia test net, and then create a request for computation, and simulate an entire verification, with the neceessary functions being called. The ProviderIncorrectSimulator.ipynb simulates what happens when a provider is incorrect, and demonstrates the slashing behavior, and likewise the file VerifierIncorrectSimulator.ipynb demonstrates what happens when a verifier is incorrect, and the slashing that takes place. Additionally, to run these files you must also have web3, eth_abi, solcx installed on your system.  In addition, to run these python files, you will need to provide a file called private_keys.json, with a json object with keys (that are Arbitrum Sepolia addresses): consumer, provider, verifier1, verifier2, verifier3, verifier4 and verifier 5, and provide private keys for each of these addresses as the values of this json object. An example would look like this (these accounts will only have Arbitrum Seplia test net tokens on them, but to collect more please use a test net faucet as these may not have sufficient tokens anymore, or use your own addresses):

```
{
    "consumer": "2ae27eeaa8095f56cd7c02adddd144bdc02d67c3d2a890b7f2ee0097cd520934",
    "provider": "efa61ee281826a391cb7113f644d97482903721d7bd3560c771e1b91676a435e",
    "verifier1": "1543215e1c43b0c70b7b69047f1a933b83b1e47e040e7f137bf379405b1ab136",
    "verifier2": "5f3a423cad7d8cf4d5c26856a0aa1d63de638db5da411eec99c85354737e41b3",
    "verifier3": "b239240ea6dea66c2473af62f696737e7473ab0194b5a47706d2e5b0fda54a89",
    "verifier4": "a697109fc85aa8c18b8e1ce76e0728d64b4803fe97155afd8f7b9f946260ebdd",
    "verifier5": "3d0d6ce1796a6e228b4ef274eeb3d44cbf828db5db35ac0af3dc7be11f8a54c6"
}
```

You will also need to provide a private key for the deployerPrivateKey variable in the 4th Jupyter cell. Please ensure that the private key of the address you specified, has enough ethereum on the Arbitrum Sepolia chain to deploy the different contracts. Also ensure that each of the addresses of the private keys you gave in the private_keys.json have enough Ethereum on the Arbitrum Seplia chain to conduct the different transactions on the chain.

To generate valid commitments, you may use the file: `contracts/commitment_generator.ipynb`, and in the variable list: verifier_addresses pass in the 5 verifier addresses you are using. To run this file, you will need to use Python 3, and will need to have web3 package installed on your system. This file will generate a nonce and the relevant commitments you will need to pass. For a successful run, all verifiers must pass in the same "Provider Answer Hash" as the <answer_hash>. To use your own private key and initialisation vector, please set the variables provider_key and initialisation_vector to the required values. Likewise for the provider_answer_hash please set this to your own hashed answer for that round.

The file `contracts/paymentAnalysis.ipynb` exists to show the expected returns participants in the market could earn depending upon market conditions. To run this file, please ensure you have matplotlib installed on your system. We make use of these graphs in chapter 5 and 6. Feel free to play around with different configurations of these graphs, by tuning the values of n and k.

Our next python file is `contracts/protocol1.ipynb`. This file demonstrates how providers create hashes of the "roots of a round" that we described in section 4. To run this file, please ensure that you have hashlib, Crypto and secrets and numpy python packages installed on your system.

Our final python file is the `contracts/Protocol1AllCorrectSimulator.ipynb`. In this file, we run a successful run of our entire marketplace, and in this case, we also integrate the features of Protocol 1 and do not use example hashes like we did in the previous python files, and we do computation over the operations file: `contracts/inputs/operations.txt`, with the rest of the files in the `contracts/inputs` directory being the input files. For this example, our provider also produces the round files in the directory `contracts/outputs`: round1.txt, round2.txt, round3.txt, round4.txt and round5.txt

Finally, to run the test cases please run: forge test --via-ir -vv using the version of forge: forge 0.2.0. This will run the test files: sanity_tests.sol, UnitTest1.sol, UnitTest2.sol, UnitTest3.sol, UnitTest4.sol. All these test files are in the `test` folder.

Alternatively, if you'd like to deploy this project yourself, please follow the instructions given below in a blank remix workspace project:

1. Please create a compiler_config.json and paste in the below json:
```
{
	"language": "Solidity",
	"settings": {
		"viaIR": true,
		"optimizer": {
			"enabled": true,
			"runs": 200
		},
		"outputSelection": {
			"*": {
			"": ["ast"],
			"*": ["abi", "metadata", "devdoc", "userdoc", "storageLayout", "evm.legacyAssembly", "evm.bytecode", "evm.deployedBytecode", "evm.methodIdentifiers", "evm.gasEstimates", "evm.assembly"]
			}
		}
	}
}
```

This allows the viaIR optimisation which is required to compile the ComputationMarket contract. After this copy and paste the contract files: COMPNFT.sol, COMPToken.sol, ComputationMarket.sol and HandlerFunctionsCompMarket.sol within a newly created folder you called contract. As you paste in these files, you will notice remix itself will create a .deps folder, and insert dependencies for the files within it. For every file we now deploy, please first compile it, and then try and deploy that file. To compile, click on the "Solidity Compiler" tab, and then to Deploy, click on the "Deploy and run transactions tab".

3. **COMPToken Deployment**
   - Constructor: Pass `1000000 * 10**18` (1 million COMP tokens with 18 decimal places).
     ```
     1000000000000000000000000
     ```
     Note that the account you are using to deploy this token with, will be your consumer account (as per the directions of these instructions, however you can create requests with any account, as long as you have the necessary tokens), and these tokens will be transferred to that consumer account. You will later transfer these tokens to the other accounts (such as the provider and the verifiers - Or if you wish, you could create a pool on Uniswap, and sell it to others there.

4. **HandlerFunctionsCompMarket Deployment**
   - This contract has no constructor parameters, so just deploy it without any input.

5. **CompNFT Deployment**
   - Like the handler contract, this contract has no constructor parameters. Deploy it without any input.

6. **ComputationMarket Deployment**
   - Constructor: Pass the addresses of the deployed `COMPToken`, `CompNFT`, and `HandlerFunctionsCompMarket` contracts in order.
     Example (replace with actual addresses):
     ```
     0xTokenAddress, 0xNFTAddress, 0xHandlerAddress
     ```

7. **Transfer NFT Ownership**
   - In the `CompNFT` contract, call the `transferNFTContractOwnership` function, passing the deployed `ComputationMarket` contract address:
     ```
     0xMarketAddress
     ```
In the below steps now, we will perform a successful request, that goes through a verification and that is successful. For the below, you will need 5 verifier addresses, 1 provider, and 1 consumer (the below assumes that the consumer is the one that deployed the COMP token, although this could be any address, but you will need to make the necessary adjustments if you are doing that).

8. **Approve COMP Tokens**
   - Before you interact with the marketplace, make sure the market contract is approved to transfer COMP tokens on behalf of the Consumer.
   - In the `COMPToken` contract, call `approve` to allow the marketplace to transfer tokens:
     ```
     0xMarketAddress, 500000000000000000000
     ```
     This will allow the market to transfer the tokens from Consumer to the market, when creating the request.

9. **Transfer Tokens to Other Accounts**
   - In `COMPToken`, use the `transfer` function to send tokens from the consumer account to the provider and verifiers:
     - For provider, pass in:
       ```
       0xProviderAddress, 1000000000000000000000
       ```
     - For verifiers (repeat for each verifier address), pass in:
       ```
       0xVerifierAddress, 500000000000000000000
       ```

       You may also perform this using metmask, or whatever wallet you are using, and send the COMP tokens to the verifiers/providers via that.

10. **Create a Request**
   - In the `ComputationMarket` contract, call `createRequest`. Here’s an example of what to pass:
     ```
     100000000000000000000, 
     10000000000000000000, 
     6000, 
     5, 
     ["https://example.com/input1", "https://example.com/input2"], 
     "https://example.com/operations", 
     <timestamp_for_computation_deadline>, 
     <timestamp_for_verification_deadline>, 
     100000, 
     3, 
     1, 
     2500, 
     0xHashOfInputFiles, 
     500000000000000000000
     ```
     You may use the following site: https://www.unixtimestamp.com/ to get the relevent timestamps you want. For sake of testing, pick timestamps that are really far away. Such as 1913122415 for computation deadline, and 1944658415 for verification. For example hash of input files, you could use: 0x52467c536c0083b7c5d02ce98e64b6a290e377272b57901250f1a3be45ff5b30

     If in the case you would like to pass in the `verifierVoteCount`, you need to call the function `createRequestWithAllowedVerifiers` and the parameters for this function are the same for `createRequest` except we add an additional parameter in the end which is the `verifierVoteCount` function.

11. **Select the Request**
    - Approve the market to transfer tokens on behalf of the provider. The amount you will need to approve the market of is: 500000000000000000000 COMP (500 COMP tokens)
    - In the `ComputationMarket` contract, the provider should call `selectRequest` with the `requestId`:
      ```
      <requestId>
      ```
      If this is the first time you created the request, and deployed the market contract, then the request Id is 0. Therefore replace requestId with 0.
      Please remember to switch acounts to the provider in your wallet when performing this transaction, since it's the provider that is meant to perform this transaction.

12. **Complete the Request**
    - The provider should complete the request by calling `completeRequest` and providing the URL to the output file:
      ```
      <requestId>, ["https://example.com/output"]
      ```
      The provider will have now recieved an NFT. Note that if this is the first time you doing doing this, the NFT Id is 0, and you can use your associated wallet to find the appropriate NFT.

13. **Apply for Verification**
    - Approve the market to take neccessary comp tokens from the verifiers. If you copied the create request section, you will need to approve: 10000000000000000000 COMP (10 COMP tokens) to the market. Although, you only need to approve 10 tokens, it might be a good idea to approve 30 tokens instead, so that way you do not need to approve again for the next two rounds. For all verifiers, you will need to perform the below function.
    - Verifiers should apply for verification by calling `applyForVerificationForRequest`:
      ```
      <requestId>
      ```

14. **Trigger Verifier Selection**
    - Verifiers can trigger the verifier selection process by calling `chooseVerifiersForRequestTrigger`:
      ```
      <requestId>
      ```
    - Perform this for all the verifiers you have applied with. When you perform this function, it will emit the event: VerifierChosen. the 2nd parameter of this event, represents the address of the verifier that was chosen to participate in this round.

15. **Submit Commitment**
    - Verifiers who are chosen for the round should submit their commitments using `submitCommitment`:
      ```
      <requestId>, <computed_hash>
      ```

16. **Reveal Provider Key and Hash**
    - The provider should reveal the key and hash for their computation by calling `revealProviderKeyAndHash`:
      ```
      <requestId>, <provider_key>, <initialisationVector>, <answer_hash>
      ```

17. **Reveal Commitment**
    - Chosen verifiers should reveal their commitment by calling `revealCommitment`:
      ```
      <requestId>, true, <answer_hash>, <nonce>
      ```

18. **Calculate Majority and Reward**
    - Verifiers should calculate the majority and recieve their reward after the round by calling `calculateMajorityAndReward`:
      ```
      <requestId>, <round_number>
      ```
