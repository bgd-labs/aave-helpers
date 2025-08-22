// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenPool {
  /// @notice Mint an amount of tokens with no additional logic.
  function directMint(address to, uint256 amount) external;

  /// @notice Gets the token bucket with its values for the block it was requested at.
  function getCurrentOutboundRateLimiterState(
    uint64 remoteChainSelector
  )
    external
    view
    returns (uint128 tokens, uint32 lastUpdated, bool isEnabled, uint128 capacity, uint128 rate);

  /// @notice Gets the token bucket with its values for the block it was requested at.
  function getCurrentInboundRateLimiterState(
    uint64 remoteChainSelector
  )
    external
    view
    returns (uint128 tokens, uint32 lastUpdated, bool isEnabled, uint128 capacity, uint128 rate);
}
