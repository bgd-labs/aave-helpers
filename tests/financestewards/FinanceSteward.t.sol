// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets} from 'aave-address-book/AaveV2Ethereum.sol';
import {FinanceSteward, IFinanceSteward} from '../../src/financestewards/FinanceSteward.sol';
import {CollectorUtils} from '../../src/financestewards/CollectorUtils.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {Ownable} from 'solidity-utils/contracts/oz-common/Ownable.sol';
import {ICollector} from 'aave-address-book/common/ICollector.sol';
import {MiscEthereum} from 'aave-address-book/MiscEthereum.sol';

/**
 * @dev Test for Finance Steward contract
 * command: make test contract-filter=FinanceSteward
 */

contract FinanceSteward_Test is Test {
  address public constant guardian = address(42);
  FinanceSteward public steward;

  address public alice = address(43);

  address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address public constant AAVE_PRICE_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;

  ICollector collector = AaveV3Ethereum.COLLECTOR;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 20520413);
    steward = new FinanceSteward(GovernanceV3Ethereum.EXECUTOR_LVL_1, guardian);
    vm.prank(0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A);
    collector.setFundsAdmin(address(steward));

    vm.prank(0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa);
    IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).transfer(
      address(AaveV3Ethereum.COLLECTOR),
      1_000_000e6
    );

    vm.prank(0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A);
    Ownable(MiscEthereum.AAVE_SWAPPER).transferOwnership(address(steward));
  }
}

contract Function_depositV3 is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.depositV3(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.depositV3(AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    steward.depositV3(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_migrateV2toV3 is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.migrateV2toV3(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.InvalidZeroAmount.selector);
    steward.migrateV2toV3(AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setMinimumBalanceShield(AaveV2EthereumAssets.USDC_A_TOKEN, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.migrateV2toV3(AaveV3EthereumAssets.USDC_UNDERLYING, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    steward.migrateV2toV3(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_withdrawV2andSwap is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.InvalidZeroAmount.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setMinimumBalanceShield(AaveV2EthereumAssets.USDC_A_TOKEN, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedToken.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_missingPriceFeed() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, address(0));
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, address(0));

    vm.startPrank(guardian);
    vm.expectRevert(FinanceSteward.MissingPriceFeed.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }
}

contract Function_withdrawV3andSwap is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.InvalidZeroAmount.selector);
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_A_TOKEN, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedToken.selector);
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_missingPriceFeed() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, address(0));
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, address(0));

    vm.startPrank(guardian);
    vm.expectRevert(FinanceSteward.MissingPriceFeed.selector);
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    steward.withdrawV3andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }
}

contract Function_tokenSwap is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.InvalidZeroAmount.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedToken.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_resvertsIf_missingPriceFeed() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, address(0));
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, address(0));

    vm.startPrank(guardian);
    vm.expectRevert(FinanceSteward.MissingPriceFeed.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING
    );
    vm.stopPrank();
  }
}

contract Function_approve is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedReceiver.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.ExceedsBalance.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance + 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.ExceedsBudget.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_transfer is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedReceiver.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.ExceedsBalance.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance + 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.ExceedsBudget.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_createStream is FinanceSteward_Test {
  uint256 public constant DURATION = 1 days;

  function test_revertsIf_notOwnerOrQuardian() public {
    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_invalidDate() public {
    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp - 1,
      block.timestamp + DURATION
    );

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.InvalidDate.selector);
    steward.createStream(alice, data);

    data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp,
      block.timestamp - 1
    );

    vm.expectRevert(FinanceSteward.InvalidDate.selector);
    steward.createStream(alice, data);

    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.UnrecognizedReceiver.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance + 1_000e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.ExceedsBalance.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.MinimumBalanceShield.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_001e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(FinanceSteward.ExceedsBudget.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_success() public {
    IFinanceSteward.StreamData memory data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp,
      block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    steward.createStream(alice, data);
    vm.stopPrank();
  }
}

contract Function_cancelStream is FinanceSteward_Test {
  uint256 public constant STREAM_ID = 100_040;

  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.cancelStream(STREAM_ID);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    steward.cancelStream(STREAM_ID);
    vm.stopPrank();
  }
}

contract Function_updateSlippage is FinanceSteward_Test {
  uint256 public constant SLIPPAGE = 100;

  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.updateSlippage(SLIPPAGE);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    steward.updateSlippage(SLIPPAGE);
    vm.stopPrank();
  }
}

contract Function_increaseBudget is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_decreaseBudget is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}

contract Function_setSwappableToken is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    // vm.expectEmit(true, true, true, true, steward);
    // emit IFinanceSteward.SwapApprovedToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    vm.stopPrank();
  }
}

contract Function_setWhitelistedReceiver is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.setWhitelistedReceiver(alice);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    // vm.expectEmit(true, true, true, true, steward);
    // emit IFinanceSteward.ReceiverWhitelisted(alice);
    steward.setWhitelistedReceiver(alice);
    vm.stopPrank();
  }
}

contract Function_setMinimumBalanceShield is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    // vm.expectEmit(true, true, true, true, steward);
    // emit IFinanceSteward.MinimumTokenBalanceUpdated(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}
