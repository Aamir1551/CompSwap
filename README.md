In this project, we create a computational marketplace on the Ethereum blockchain as per my thesis. We will deploy this DApp on the Arbitrum Blockchain. 

Note that the COMP token is equal to 18**18 COMP units, since the COMP token follows the ERC20 standard.

You can run this project, by running the relevant python file: AllCorrectSimulator.ipynb
In that file, we do a successful verification run of a request which we also deploy on the Arbiturm sepolia test net.

Alternatively, if you'd like to deploy this project yourself, please follow the instructions given below in a blank remix workspace project:

1. Please create a compiler_config.json and paste in the below json:
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

This allows the viaIR optimisation which is required to compile the ComputationMarket contract. After this copy and paste the contract files: COMPNFT.sol, COMPToken.sol, ComputationMarket.sol and HandlerFunctionsCompMarket.sol within a newly created folder you called contract. As you paste in these files, you will notice remix itself will create a .deps folder, and insert dependencies for the files within it. For every file we now deploy, please first compile it, and then try and deploy that file. To compile, click on the "Solidity Compiler" tab, and then to Deploy, click on the "Deploy and run transactions tab".

3. **COMPToken Deployment**
   - Constructor: Pass `1000000 * 10**18` (1 million COMP tokens with 18 decimal places).
     ```
     1000000000000000000000000
     ```
     Note that the account you are using to deploy this token with, will be your consumer account, and these million tokens will be transferred to you. You will later transfer these million tokens to the other accounts. (Or if you wish, you could create a pool on Uniswap, and sell it to others there)

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
     - For provider:
       ```
       0xProviderAddress, 1000000000000000000000
       ```
     - For verifiers (repeat for each verifier address):
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

11. **Select the Request**
    - Approve the market to transfer tokens on behalf of the provider. The amount you will need to approve the market of is: 500000000000000000000 COMP (500 COMP tokens)
    - In the `ComputationMarket` contract, the provider should call `selectRequest` with the `requestId`:
      ```
      <requestId>
      ```
      If this is the first time you created the request, and deployed the market contract, then the request Id is 0. Therefore replace requestId with 0
      Please ensure to switch acounts to the provider in your wallet. 

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
    - Verifiers should calculate the majority and reward after the round by calling `calculateMajorityAndReward`:
      ```
      <requestId>, <round_number>
      ```


To generate valid commitments, you may use the file: commitment_generator, and in the variable list: verifier_addresses pas in the 5 verifier addresses you are using.

This file will generate a nonce and the relevant commitments you will need to pass. For a successful run, all verifiers must pass in the "Provider Answer Hash" as the <answer_hash>
