// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {Rescuable} from 'solidity-utils/contracts/utils/Rescuable.sol';
import {OwnableWithGuardian} from 'solidity-utils/contracts/access-control/OwnableWithGuardian.sol';
import {Initializable} from 'solidity-utils/contracts/transparent-proxy/Initializable.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

import {IPriceChecker} from './interfaces/IExpectedOutCalculator.sol';
import {IMilkman} from './interfaces/IMilkman.sol';
import {IAggregatorV3Interface} from './interfaces/IAggregatorV3Interface.sol';
import {IAaveSwapper} from './IAaveSwapper.sol';

/// @title AaveSwapper
/// @author Llama
/// @notice Helper contract to swap assets using milkman
contract AaveSwapper is IAaveSwapper, Initializable, OwnableWithGuardian, Rescuable {
  using SafeERC20 for IERC20;

  address public constant BAL80WETH20 = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;

  /// @notice Initializes the contract.
  /// Reverts if already initialized
  function initialize() external initializer {
    _transferOwnership(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    _updateGuardian(0xA519a7cE7B24333055781133B13532AEabfAC81b);
  }

  /// @inheritdoc IAaveSwapper
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
  ) external onlyOwner {
    bytes memory data = _getPriceCheckerAndData(toToken, fromOracle, toOracle, slippage);

    _swap(milkman, priceChecker, fromToken, toToken, recipient, amount, data);

    emit SwapRequested(
      milkman,
      fromToken,
      toToken,
      fromOracle,
      toOracle,
      amount,
      recipient,
      slippage
    );
  }

  /// @inheritdoc IAaveSwapper
  function limitSwap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwner {
    _swap(milkman, priceChecker, fromToken, toToken, recipient, amount, abi.encode(amountOut));

    emit LimitSwapRequested(milkman, fromToken, toToken, amount, recipient, amountOut);
  }

  /// @inheritdoc IAaveSwapper
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
  ) external onlyOwnerOrGuardian {
    bytes memory data = _getPriceCheckerAndData(toToken, fromOracle, toOracle, slippage);

    _cancelSwap(tradeMilkman, priceChecker, fromToken, toToken, recipient, amount, data);
  }

  /// @inheritdoc IAaveSwapper
  function cancelLimitSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwnerOrGuardian {
    _cancelSwap(
      tradeMilkman,
      priceChecker,
      fromToken,
      toToken,
      recipient,
      amount,
      abi.encode(amountOut)
    );
  }

  /// @inheritdoc IAaveSwapper
  function getExpectedOut(
    address priceChecker,
    uint256 amount,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle
  ) public view returns (uint256) {
    bytes memory data = _getPriceCheckerAndData(toToken, fromOracle, toOracle, 0);

    (, bytes memory _data) = abi.decode(data, (uint256, bytes));

    return
      IPriceChecker(priceChecker).EXPECTED_OUT_CALCULATOR().getExpectedOut(
        amount,
        fromToken,
        toToken,
        _data
      );
  }

  /// @inheritdoc Rescuable
  function whoCanRescue() public view override returns (address) {
    return owner();
  }

  /// @notice Internal function that handles swaps
  /// @param milkman Address of the Milkman contract to submit the order
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param priceCheckerData abi-encoded data for price checker
  function _swap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    bytes memory priceCheckerData
  ) internal {
    if (fromToken == address(0) || toToken == address(0)) revert Invalid0xAddress();
    if (recipient == address(0)) revert InvalidRecipient();
    if (amount == 0) revert InvalidAmount();

    IERC20(fromToken).forceApprove(milkman, amount);

    IMilkman(milkman).requestSwapExactTokensForTokens(
      amount,
      IERC20(fromToken),
      IERC20(toToken),
      recipient,
      priceChecker,
      priceCheckerData
    );
  }

  /// @notice Internal function that handles swap cancellations
  /// @param tradeMilkman Address of the Milkman contract to submit the order
  /// @param priceChecker Address of the price checker to validate order
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param recipient Address of the account receiving the swapped funds
  /// @param amount The amount of fromToken to swap
  /// @param priceCheckerData abi-encoded data for price checker
  function _cancelSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    bytes memory priceCheckerData
  ) internal {
    IMilkman(tradeMilkman).cancelSwap(
      amount,
      IERC20(fromToken),
      IERC20(toToken),
      recipient,
      priceChecker,
      priceCheckerData
    );

    IERC20(fromToken).safeTransfer(
      address(AaveV3Ethereum.COLLECTOR),
      IERC20(fromToken).balanceOf(address(this))
    );

    emit SwapCanceled(fromToken, toToken, amount);
  }

  /// @notice Helper function to abi-encode data for price checker
  /// @param toToken Address of the token to swap to
  /// @param fromOracle Address of the oracle to check fromToken price
  /// @param toOracle Address of the oracle to check toToken price
  /// @param slippage The allowed slippage compared to the oracle price (in BPS)
  function _getPriceCheckerAndData(
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 slippage
  ) internal view returns (bytes memory) {
    if (toToken == BAL80WETH20) {
      return abi.encode(slippage, '');
    } else {
      return abi.encode(slippage, _getChainlinkCheckerData(fromOracle, toOracle));
    }
  }

  /// @notice Helper function to abi-encode Chainlink oracle data
  /// @param fromOracle Address of the oracle to check fromToken price
  /// @param toOracle Address of the oracle to check toToken price
  function _getChainlinkCheckerData(
    address fromOracle,
    address toOracle
  ) internal view returns (bytes memory) {
    if (fromOracle == address(0) || toOracle == address(0)) revert OracleNotSet();
    if (!(IAggregatorV3Interface(fromOracle).decimals() > 0)) revert InvalidOracle();
    if (!(IAggregatorV3Interface(toOracle).decimals() > 0)) revert InvalidOracle();

    address[] memory paths = new address[](2);
    paths[0] = fromOracle;
    paths[1] = toOracle;

    bool[] memory reverses = new bool[](2);
    reverses[1] = true;

    return abi.encode(paths, reverses);
  }
}
