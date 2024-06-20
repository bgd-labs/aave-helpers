// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAaveSwapper {
    event LimitSwapRequested(
    address milkman,
    address indexed fromToken,
    address indexed toToken,
    uint256 amount,
    address indexed recipient,
    uint256 minAmountOut
  );
  event SwapCanceled(address indexed fromToken, address indexed toToken, uint256 amount);
  event SwapRequested(
    address milkman,
    address indexed fromToken,
    address indexed toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    address indexed recipient,
    uint256 slippage
  );

  /// @notice Provided address is zero address
  error Invalid0xAddress();

  /// @notice Amount needs to be greater than zero
  error InvalidAmount();

  /// @notice Oracle does not have a valid decimals() function
  error InvalidOracle();

  /// @notice Recipient cannot be the zero address
  error InvalidRecipient();

  /// @notice Oracle cannot be the zero address
  error OracleNotSet();

  /// @notice Function to swap one token for another within a specified slippage
  /// @param milkman Address of the Milkman contract to submit the order
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param fromOracle Address of the oracle to check fromToken price
  /// @param toOracle Address of the oracle to check toToken price
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param slippage The allowed slippage compared to the oracle price (in BPS)
  function swap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
  ) external;

  /// @notice Function to swap one token for another with a limit price
  /// @param milkman Address of the Milkman contract to submit the order
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param amountOut The limit price of the toToken (minimium amount to receive)
  /// @dev For amountOut, use the token's atoms for decimals (ie: 6 for USDC, 18 for DAI)
  function limitSwap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external;

  /// @notice Function to cancel an existing swap
  /// @param tradeMilkman Address of the Milkman contract created upon order submission
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param fromOracle Address of the oracle to check fromToken price
  /// @param toOracle Address of the oracle to check toToken price
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param slippage The allowed slippage compared to the oracle price (in BPS)
  function cancelSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
  ) external;

  /// @notice Function to cancel an existing limit swap
  /// @param tradeMilkman Address of the Milkman contract created upon order submission
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param amountOut The limit price of the toToken (minimium amount to receive)
  function cancelLimitSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external;

  /// @notice Helper function to see how much one could expect return in a swap
  /// @param priceChecker Address of the price checker to validate order
  /// @param amount The amount of fromToken to swap
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param fromOracle Address of the oracle to check fromToken price
  /// @param toOracle Address of the oracle to check toToken price
  function getExpectedOut(
    address priceChecker,
    uint256 amount,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle
  ) external view returns (uint256);
}
