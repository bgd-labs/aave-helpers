// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {Ownable} from 'solidity-utils/contracts/oz-common/Ownable.sol';
import {Rescuable} from 'solidity-utils/contracts/utils/Rescuable.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';

import {ChainIds} from '../../ChainIds.sol';
import {IAavePolEthPlasmaBridge} from './IAavePolEthPlasmaBridge.sol';

interface IERC20Polygon {
  /// @param account Address of the account to query
  function balanceOf(address account) external view returns (uint256);

  /// @param to The adress to send tokens to
  /// @param amount The amount of tokens to transfer
  function transfer(address to, uint256 amount) external returns (bool);

  /// @dev First step in bridging tokens
  /// @param amount The amount of tokens to withdraw (bridge)
  function withdraw(uint256 amount) external payable;
}

interface IERC20PredicateBurnOnly {
  /// @dev Function needs to be called in order to confirm a withdrawal
  /// @param data The generated proof to confirm a withdrawal transaction
  function startExitWithBurntTokens(bytes calldata data) external;
}

interface IWithdrawManager {
  /// @dev Last step in exiting a token bridge
  /// @param _token Address of the token being withdrawn
  function processExits(address _token) external;

  /// @dev Last step in exiting a multi-token bridge
  /// @param _tokens Array of token addresses being withdrawn
  function processExitsBatch(address[] calldata _tokens) external;
}

/// @title AavePolEthPlasmaBridge
/// @author efecarranza.eth
/// @notice Helper contract to bridge assets from Polygon to Ethereum
contract AavePolEthPlasmaBridge is Ownable, Rescuable, IAavePolEthPlasmaBridge {
  using SafeERC20 for IERC20;

  /// @dev The called method is not available on this chain
  error InvalidChain();

    /// @dev Emitted when a bridge is initiated
  event Bridge(address token, uint256 amount);

  /// @dev Emitted when the bridge transaction is confirmed
  event ConfirmExit(bytes proof);

  /// @dev Emitted when a token bridge is finalized
  event Exit(address indexed token);

    /// @dev Emitted when multiple token bridges are finalized
  event ExitBatch(address[] indexed tokens);

  /// @dev Emitted when token is withdrawn to the Aave Collector
  event WithdrawToCollector(address token, uint256 amount);

  /// @dev The mainnet address of the Predicate contract to confirm withdrawal
  address public constant ERC20_PREDICATE_BURN = 0x158d5fa3Ef8e4dDA8a5367deCF76b94E7efFCe95;

  /// @dev The address of Matic on Polygon
  address public constant NATIVE_MATIC = 0x0000000000000000000000000000000000001010;

  /// @dev The mainnet address of the withdrawal contract to exit the bridge
  address public constant WITHDRAW_MANAGER = 0x2A88696e0fFA76bAA1338F2C74497cC013495922;

  /// @param _owner The owner of the contract upon deployment
  constructor(address _owner) {
    _transferOwnership(_owner);
  }

  /// @inheritdoc IAavePolEthPlasmaBridge
  function bridge(address token, uint256 amount) external onlyOwner {
    if (block.chainid != ChainIds.POLYGON) revert InvalidChain();

    IERC20Polygon(token).withdraw{value: amount}(amount);
    emit Bridge(token, amount);
  }

  /// @inheritdoc IAavePolEthPlasmaBridge
  function confirmExit(bytes calldata burnProof) external {
    if (block.chainid != ChainIds.MAINNET) revert InvalidChain();

    IERC20PredicateBurnOnly(0x158d5fa3Ef8e4dDA8a5367deCF76b94E7efFCe95).startExitWithBurntTokens(
      burnProof
    );
    emit ConfirmExit(burnProof);
  }

  /// @inheritdoc IAavePolEthPlasmaBridge
  function exit(address token) external {
    if (block.chainid != ChainIds.MAINNET) revert InvalidChain();

    IWithdrawManager(WITHDRAW_MANAGER).processExits(token);
    emit Exit(token);
  }

  /// @inheritdoc IAavePolEthPlasmaBridge
  function withdrawToCollector(address token) external {
    if (block.chainid != ChainIds.MAINNET) revert InvalidChain();

    uint256 balance = IERC20(token).balanceOf(address(this));

    IERC20(token).safeTransfer(address(AaveV3Ethereum.COLLECTOR), balance);
    emit WithdrawToCollector(token, balance);
  }

  /// @inheritdoc Rescuable
  function whoCanRescue() public view override returns (address) {
    return owner();
  }

  /// @dev Allows the contract to receive Matic on Polygon
  receive() external payable {
    if (block.chainid != ChainIds.POLYGON) revert InvalidChain();
  }
}
