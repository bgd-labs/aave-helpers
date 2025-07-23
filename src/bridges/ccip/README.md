# AaveGhoCcipBridge

The AaveGhoCcipBridge is a contract to facilitate moving GHO from Ethereum Mainnet to various L2 networks utilizing the underlying CCIP infrastructure from Chainlink.

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
