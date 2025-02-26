## AaveCcipGhoBridge Smart Contract

### Overview

The `AaveCcipGhoBridge` smart contract facilitates the secure bridging of GHO tokens across different blockchain networks using Chainlink's Cross-Chain Interoperability Protocol (CCIP). By leveraging Chainlink's decentralized infrastructure, it ensures reliable and transparent cross-chain token transfers while using GHO tokens exclusively for fees.

### Key Components

1. **Router and GHO Addresses**:
   - **`ROUTER`**: The Chainlink CCIP router address for cross-chain communication.
   - **`GHO`**: Address of the GHO token, which the contract bridges across chains.

2. **Bridges Mapping**:
   - A mapping of destination chain selectors (chain identifiers) to corresponding bridge addresses on the destination chains.

### Main Functionalities

1. **Token Transfers**:
   - Facilitates secure GHO token transfers between chains.  
   - Collects GHO tokens from the sender, validates the destination chain and bridge configuration, and transfers the tokens via Chainlink CCIP.  
   - The `checkDestination` modifier ensures that the destination chain and bridge are properly configured before any transfer.
   - When user call this function, it sends gho from bridge contract first. And if balance of bridge is insufficient, it pull gho from user

2. **Fee Payment**:
   - Fees are paid exclusively in GHO and ETH.  
   - Calculates the required fee for a transfer and deducts it directly from the user's GHO balance.

3. **Cross-Chain Message Handling**:
   - Processes incoming cross-chain messages using the `_ccipReceive` function.  
   - Decodes the message, verifies its authenticity, and releases the corresponding GHO tokens to the recipient on the destination chain.

4. **Quote Transfer**:
   - The `quoteTransfer` function allows users to estimate the GHO fee required for a transfer without executing the transfer.

5. **Setting Destination Bridges**:
   - The contract owner can configure or update the bridge addresses for different destination chains via the `setDestinationBridge` function.

### Security Features

- **Role-Based Access Control**:  
  Uses `AccessControl` to manage permissions:  
  - `DEFAULT_ADMIN_ROLE`: Grants administrative rights.  
  - `BRIDGER_ROLE`: Restricts who can initiate bridging operations.  
  This ensures that only authorized users can perform critical functions.  

- **Destination Validation**:  
  The `checkDestination` modifier ensures that the destination chain and bridge address are properly configured before executing transfers.

- **Token Approval Management**:  
  Securely handles GHO token approvals for the router, mitigating over-approval risks.

- **Rescue Functionality**:  
  Implements a `Rescuable` mechanism, allowing the `EXECUTOR` to rescue funds in emergencies while maintaining security boundaries.

- **CCIP Sender and Receiver Validation**:  
  - Verifies messages originate from the correct source bridge using Chainlink CCIP.  
  - Incoming messages must match the expected sender address for the specified source chain.

### Events

- **TransferIssued**: Emitted when a transfer is successfully initiated.  
- **TransferFinished**: Emitted when a transfer completes successfully on the destination chain.  
- **DestinationUpdated**: Emitted when a new bridge address is set for a specific chain.

### Error Handling

- **UnsupportedChain**: Thrown when attempting to transfer to an unsupported destination chain.  
- **InvalidTransferAmount**: Thrown when the total amount of tokens to transfer is zero.  
- **InsufficientFee**: Thrown if the provided fee is insufficient to cover the transaction.  
- **InvalidMessage**: Thrown when a message received from a source chain does not come from the expected bridge address.

### Deployed Addresses

Mainnet: [0x5648f519b2064ff30385828e76fefda749749ac2](https://etherscan.io/address/0x5648f519b2064ff30385828e76fefda749749ac2), Arbitrum: [0x03f589a825ee129c5c6d2f6ef5c259870019567b](https://arbiscan.io/address/0x03f589a825ee129c5c6d2f6ef5c259870019567b)


Confirmed Bridges:

| Direct                | CCIP Message ID | Source Tx | Destination Tx |
| ---------------- | ---------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Ethereum -> Arbitrum  | [0x87790f04c4cef490f46143efd7086147326ac65a3421c4aca82dd251f55bef82](https://ccip.chain.link/msg/0x87790f04c4cef490f46143efd7086147326ac65a3421c4aca82dd251f55bef82)  | [0xa0c72c9e705ce20bb53ba0a57d249d082930d791c3f733a95ea07398b946e4b3](https://etherscan.io/tx/0xa0c72c9e705ce20bb53ba0a57d249d082930d791c3f733a95ea07398b946e4b3)  | [0xcea9e503c001119535abf0016f3e2ccc8e71fe0e202522dec92dd52811334393](https://arbiscan.io/tx/0xcea9e503c001119535abf0016f3e2ccc8e71fe0e202522dec92dd52811334393) |
| Arbitrum -> Ethereum  | [0xe7eae1ddf0138b4a410a46b801aecbd1ca2ef29750980625fafa12adcf37946f](https://ccip.chain.link/msg/0xe7eae1ddf0138b4a410a46b801aecbd1ca2ef29750980625fafa12adcf37946f) | [0xa9751980b3a66903031a9751d92ab56c331ad76916fea9b21ac3a92f8970d743](https://arbiscan.io/tx/0xa9751980b3a66903031a9751d92ab56c331ad76916fea9b21ac3a92f8970d743) | [0x5310d08839775003e63a763c73721491d51439aea43de6b298388790922b8ba3](https://etherscan.io/tx/0x5310d08839775003e63a763c73721491d51439aea43de6b298388790922b8ba3) |

### Conclusion
The `AaveCcipGhoBridge` smart contract provides a robust mechanism for bridging GHO tokens across multiple chains via Chainlink's CCIP. It offers flexibility in fee payments, supports secure cross-chain transfers, and allows for easy configuration of destination bridges.