// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAaveCcipGhoBridge {
  /// @dev Fee payment token
  enum PayFeesIn {
    Native,
    LINK
  }

  /**
   * @notice Transfers tokens to the destination chain and distributes them
   * @param destinationChainSelector The selector of the destination chain
   * @param amount The amount to transfer
   * @param payFeesIn The fee payment method
   * @return messageId The ID of the cross-chain message
   */
  function transfer(
    uint64 destinationChainSelector,
    uint256 amount,
    PayFeesIn payFeesIn
  ) external payable returns (bytes32 messageId);

  /**
   * @notice calculates fee amount to exeucte transfers
   * @param destinationChainSelector The selector of the destination chain
   * @param amount The amount to transfer
   * @param payFeesIn The fee payment method
   * @return fee The amount of fee
   */
  function quoteTransfer(
    uint64 destinationChainSelector,
    uint256 amount,
    PayFeesIn payFeesIn
  ) external view returns (uint256 fee);

  /**
   * @dev Emits when a new token transfer is issued
   * @param messageId The ID of the cross-chain message
   * @param destinationChainSelector The selector of the destination chain
   * @param amount The total amount of GHO tokens
   */
  event TransferIssued(
    bytes32 indexed messageId,
    uint64 indexed destinationChainSelector,
    uint256 amount
  );

  /**
   * @dev Emits when the token transfer is executed on the destination chain
   * @param messageId The ID of the cross-chain message
   */
  event TransferFinished(bytes32 indexed messageId);

  /**
   * @dev Emits when the destination bridge data is updated
   * @param chainSelector The selector of the destination chain
   * @param bridge The address of the bridge on the destination chain
   */
  event DestinationUpdated(uint64 indexed chainSelector, address indexed bridge);

  /// @dev Returns this error when the destination chain is not set up
  error UnsupportedChain();

  /// @dev Returns this error when the native fee amount is below the required amount
  error InsufficientFee();

  /// @dev Returns this error when the total amount is zero
  error InvalidTransferAmount();

  /// @dev Returns this error when the message comes from an invalid bridge
  error InvalidMessage();
}
