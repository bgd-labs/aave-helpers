# AaveGhoCcipBridge

The AaveGhoCcipBridge is a contract to facilitate moving GHO from Ethereum Mainnet to other networks utilizing the underlying CCIP infrastructure from Chainlink. The GHO obtained on the receiving network is immediately transferred automatically to the COLLECTOR instance of that network.

# Funding

The contract must be funded with fee tokens in order for the message to be executed. Most networks will support GHO as a fee token, but in case it is not supported at the beginning, LINK can be used.
During a governance proposal, GHO/LINK can be sent to the CCIP instance that will be bridging the GHO tokens to another network.
The easiest flow is to have the contract funded with tokens beforehand as it's very cheap to bridge.

From mainnet to another network the cost of a message is ~1.50. From a non-mainnet network to Mainnet the cost is ~0.50.
Billing costs can be found [here](https://docs.chain.link/ccip/billing)

# Permissions

The contract implements AccessControl for permissioned functions.
The DEFAULT_ADMIN will always be the respective network's Level 1 Executor (Governance).
The BRIDGER_ROLE will be given to "Facilitator" type contracts to mint and then bridge GHO.

# Security Considerations

A new destination chain and corresponding bridge contract must be previously pre-approved by governance.
The contract inherits from `Rescuable`. Using the inherited functions it can transfer tokens out from this contract.
In the case of malformed or invalid messages, the contract implements a rescue mechanism to send tokens to the Collector contract,
following CCIP's defensive approach as shown here:
https://github.com/smartcontractkit/chainlink/blob/62c23768cd483b179301625603a785dd773f2c78/contracts/src/v0.8/ccip/applications/DefensiveExample.sol

# Destination Chains

The chain selector for a given chain is defined by CCIP. The list of chain selectors can be found here:
https://docs.chain.link/ccip/directory/mainnet

Non-EVM chains are supported.

The destination chain address must be provided as bytes. For EVM chains, convert the address to bytes with `abi.encode(address)`, where address if an EVM address. For Solana/Aptos, `abi.encode(bytes32)` where bytes32 is the Aptos/Solana address.
