### Overview
The `AaveCcipGhoBridge` smart contract is a custom implementation designed to facilitate the bridging of GHO tokens between different blockchain networks using Chainlink's Cross-Chain Interoperability Protocol (CCIP). It enables token transfers between chains in a secure and decentralized manner by leveraging Chainlink's infrastructure. Here's an overview of its key features and components:

### Key Components
1. **Router, LINK, GHO Addresses**:
   - **`ROUTER`**: The Chainlink CCIP router address used for cross-chain communication.
   - **`LINK`**: Address of the Chainlink token (LINK), used for paying transaction fees when required.
   - **`GHO`**: Address of the GHO token, which the contract helps bridge across chains.

2. **Bridges Mapping**: 
   - A mapping of destination chain selectors (chain identifiers) to the corresponding bridge address on the destination chain.

### Main Functionalities
1. **Token Transfers**:
   - The contract allows users to transfer GHO tokens from one blockchain to another. It collects all GHO tokens from the sender, validates the transfer, and sends the tokens via Chainlink CCIP to the specified destination chain.
   - A modifier `checkDestination` ensures the destination chain and bridge are properly configured.

2. **Fee Payment**:
   - Users can pay fees in either LINK tokens or native gas tokens of the chain (e.g., ETH).
   - The contract calculates the required fees via the `IRouterClient.getFee` method and handles fee payments accordingly.

3. **Cross-Chain Message Handling**:
   - When a cross-chain message is received, the `_ccipReceive` function decodes the message, verifies its authenticity, and releases the corresponding GHO tokens to the specified recipients on the destination chain.

4. **Quote Transfer**:
   - This function, `quoteTransfer`, allows users to estimate the fee required for a token transfer without actually performing the transfer.

5. **Setting Destination Bridges**:
   - The contract owner can configure or update the bridge addresses for different destination chains through the `setDestinationBridge` function.

### Security Features
- **Ownership Control**: The contract uses OpenZeppelin's `Ownable` contract to ensure only the owner can configure or update key components like destination bridges.
- **Validation**: It checks whether the destination chain and bridge address are valid before executing transfers, ensuring that users cannot send tokens to unsupported chains.

### Events
- **TransferIssued**: Emitted when a transfer is successfully initiated.
- **TransferFinished**: Emitted when a transfer completes successfully on the destination chain.
- **DestinationUpdated**: Emitted when a new bridge address is set for a specific chain.

### Error Handling
- **UnsupportedChain**: Thrown when attempting to transfer to an unsupported destination chain.
- **InvalidTransferAmount**: Thrown when the total amount of tokens to transfer is zero.
- **InsufficientFee**: Thrown if the provided fee is insufficient to cover the transaction.
- **InvalidMessage**: Thrown when the message received from a source chain does not come from the expected bridge address.

### Deployed Addresses

Mainnet: [0x5648f519b2064ff30385828e76fefda749749ac2](https://etherscan.io/address/0x5648f519b2064ff30385828e76fefda749749ac2), Arbitrum: [0x03f589a825ee129c5c6d2f6ef5c259870019567b](https://arbiscan.io/address/0x03f589a825ee129c5c6d2f6ef5c259870019567b)


Confirmed Bridges:

| Direct                | CCIP Message ID | Source Tx | Destination Tx |
| ---------------- | ---------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Ethereum -> Arbitrum  | [0x87790f04c4cef490f46143efd7086147326ac65a3421c4aca82dd251f55bef82](https://ccip.chain.link/msg/0x87790f04c4cef490f46143efd7086147326ac65a3421c4aca82dd251f55bef82)  | [0xa0c72c9e705ce20bb53ba0a57d249d082930d791c3f733a95ea07398b946e4b3](https://etherscan.io/tx/0xa0c72c9e705ce20bb53ba0a57d249d082930d791c3f733a95ea07398b946e4b3)  | [0xcea9e503c001119535abf0016f3e2ccc8e71fe0e202522dec92dd52811334393](https://arbiscan.io/tx/0xcea9e503c001119535abf0016f3e2ccc8e71fe0e202522dec92dd52811334393) |
| Arbitrum -> Ethereum  | [0xe7eae1ddf0138b4a410a46b801aecbd1ca2ef29750980625fafa12adcf37946f](https://ccip.chain.link/msg/0xe7eae1ddf0138b4a410a46b801aecbd1ca2ef29750980625fafa12adcf37946f) | [0xa9751980b3a66903031a9751d92ab56c331ad76916fea9b21ac3a92f8970d743](https://arbiscan.io/tx/0xa9751980b3a66903031a9751d92ab56c331ad76916fea9b21ac3a92f8970d743) | [0x5310d08839775003e63a763c73721491d51439aea43de6b298388790922b8ba3](https://etherscan.io/tx/0x5310d08839775003e63a763c73721491d51439aea43de6b298388790922b8ba3) |

### Conclusion
The `AaveCcipGhoBridge` smart contract provides a robust mechanism for bridging GHO tokens across multiple chains via Chainlink's CCIP. It offers flexibility in fee payments, supports secure cross-chain transfers, and allows for easy configuration of destination bridges.