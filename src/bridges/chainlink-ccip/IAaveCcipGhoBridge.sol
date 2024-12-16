// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';

interface IAaveCcipGhoBridge {
  /**
   * @dev Emits when a new token transfer is issued
   * @param messageId The ID of the cross-chain message
   * @param destinationChainSelector The selector of the destination chain
   *        chain selector can be found https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet
   * @param from The address of sender on source chain
   * @param amount The total amount of GHO tokens
   */
  event TransferIssued(
    bytes32 indexed messageId,
    uint64 indexed destinationChainSelector,
    address indexed from,
    uint256 amount
  );

  /**
   * @dev Emits when the token transfer is executed on the destination chain
   * @param messageId The ID of the cross-chain message
   * @param to The address of receiver on destination chain
   * @param amount The amount of token to translated
   */
  event TransferFinished(bytes32 indexed messageId, address indexed to, uint256 amount);

  /**
   * @dev Emits when the destination bridge data is updated
   * @param chainSelector The selector of the destination chain
   * @param bridge The address of the bridge on the destination chain
   */
  event DestinationUpdated(uint64 indexed chainSelector, address indexed bridge);

  /**
   * @dev Emits when receive invalid message
   * @param messageId The id of message
   */
  event ReceivedInvalidMessage(bytes32 indexed messageId);

  /**
   * @dev Emits when receive invalid message
   * @param messageId The id of message
   */
  event HandledInvalidMessage(bytes32 indexed messageId);

  /// @dev Returns this error when the destination chain is not set up
  error UnsupportedChain();

  /// @dev Returns this error when the total amount is zero
  error InvalidTransferAmount();

  /// @dev Returns this error when message not found
  error MessageNotFound();

  /// @dev Emits when a function is called outside of the contract itself.
  error OnlySelf();

  /**
   * @notice Transfers tokens to the destination chain and distributes them
   * @param destinationChainSelector The selector of the destination chain
   *        chain selector can be found https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet
   * @param amount The amount to transfer
   * @param gasLimit Gas limit for the callback on the destination chain. If this value is 0, uses default value
   * @return messageId The ID of the cross-chain message
   */
  function bridge(
    uint64 destinationChainSelector,
    uint256 amount,
    uint256 gasLimit
  ) external payable returns (bytes32 messageId);

  /**
   * @notice calculates fee amount to exeucte transfers
   * @param destinationChainSelector The selector of the destination chain
   *        chain selector can be found https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet
   * @param amount The amount to transfer
   * @param gasLimit Gas limit for the callback on the destination chain. If this value is 0, uses default value
   * @return fee The amount of fee
   */
  function quoteBridge(
    uint64 destinationChainSelector,
    uint256 amount,
    uint256 gasLimit
  ) external view returns (uint256 fee);

  /**
   * @notice handle invalid message
   * @param messageId The id of message
   */
  function handleInvalidMessage(bytes32 messageId) external;

  /**
   * @notice Returns content of invalid message
   * @param messageId The id of message
   * @return message Message data
   */
  function getInvalidMessage(
    bytes32 messageId
  ) external view returns (Client.Any2EVMMessage memory message);
}
