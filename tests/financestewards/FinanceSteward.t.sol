// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets} from 'aave-address-book/AaveV2Ethereum.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {Ownable} from 'solidity-utils/contracts/oz-common/Ownable.sol';
import {ICollector} from 'aave-address-book/common/ICollector.sol';
import {MiscEthereum} from 'aave-address-book/MiscEthereum.sol';
import {Collector} from 'aave-v3-origin/contracts/treasury/Collector.sol';

import {FinanceSteward, IFinanceSteward} from 'src/financestewards/FinanceSteward.sol';
import {AggregatorInterface} from 'src/financestewards/AggregatorInterface.sol';
import {CollectorUtils} from 'src/CollectorUtils.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';


/**
 * Helper contract to mock price feed calls
 */
contract MockOracle {
  function decimals() external view returns (uint8) {
    return 8;
  }

  function latestAnswer() external view returns (int256) {
    return 0;
  }
}

/*
 * Oracle missing `decimals` implementation thus invalid.
 */
contract InvalidMockOracle {
  function latestAnswer() external view returns (int256) {
    return 0;
  }
}

/**
 * @dev Test for Finance Steward contract
 * command: make test-financesteward
 */
contract FinanceSteward_Test is Test {
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
  event BudgetUpdate(address indexed token, uint newAmount);
  event SwapApprovedToken(address indexed token, address indexed oracleUSD);
  event ReceiverWhitelisted(address indexed receiver);
  event MinimumTokenBalanceUpdated(address indexed token, uint newAmount);

  address public constant guardian = address(42);
  FinanceSteward public steward;

  address public alice = address(43);

  address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address public constant AAVE_PRICE_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
  address public constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
  address public constant COLLECTOR_PROXY = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;

  ICollector collector = AaveV3Ethereum.COLLECTOR;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));
    steward = new FinanceSteward(GovernanceV3Ethereum.EXECUTOR_LVL_1, guardian);

    address new_collector_impl = new Collector();

    vm.prank(EXECUTOR);

    vm.expectEmit(true, true);
    emit Upgraded(new_collector_impl);
    TransparentUpgradeableProxy(address(collector)).upgradeTo(new_collector_impl);
    
    IAccessControl(ACL_MANAGER).grantRole(collector.FUNDS_ADMIN_ROLE(), steward);
    IAccessControl(ACL_MANAGER).grantRole(collector.FUNDS_ADMIN_ROLE(), EXECUTOR);

    vm.stopPrank();

     vm.prank(0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa); //RANDOM USDC HOLDER
    IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).transfer(
      address(AaveV3Ethereum.COLLECTOR),
      1_000_000e6
    );

    vm.prank(EXECUTOR);
    Ownable(MiscEthereum.AAVE_SWAPPER).transferOwnership(address(steward));
  }
}

contract Function_depositV3 is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    vm.startPrank(guardian);

    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertGt(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceBefore
    );
    vm.stopPrank();
  }
}

contract Function_migrateV2toV3 is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.migrateV2toV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.InvalidZeroAmount.selector);
    steward.migrateV2toV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_resvertsIf_minimumBalanceShield() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setMinimumBalanceShield(AaveV2EthereumAssets.USDC_A_TOKEN, 1_000e6);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.migrateV2toV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.startPrank(guardian);

    steward.migrateV2toV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertLt(
      IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceV2Before
    );
    assertGt(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceV3Before
    );
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
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.InvalidZeroAmount.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.UnrecognizedToken.selector);
    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    uint256 slippage = 100;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    vm.expectEmit(true, true, true, true, address(steward.SWAPPER()));
    emit SwapRequested(
      steward.MILKMAN(),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      USDC_PRICE_FEED,
      AAVE_PRICE_FEED,
      1_000e6,
      address(AaveV3Ethereum.COLLECTOR),
      slippage
    );

    steward.withdrawV2andSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      slippage
    );

    assertLt(
      IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceV2Before
    );

    vm.stopPrank();
  }
}

contract Function_withdrawV3andSwap is FinanceSteward_Test {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    steward.withdrawV3andSwap(
      address(AaveV3Ethereum.POOL),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.InvalidZeroAmount.selector);
    steward.withdrawV3andSwap(
      address(AaveV3Ethereum.POOL),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.withdrawV3andSwap(
      address(AaveV3Ethereum.POOL),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.UnrecognizedToken.selector);
    steward.withdrawV3andSwap(
      address(AaveV3Ethereum.POOL),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    uint256 slippage = 100;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    vm.expectEmit(true, true, true, true, address(steward.SWAPPER()));
    emit SwapRequested(
      steward.MILKMAN(),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      USDC_PRICE_FEED,
      AAVE_PRICE_FEED,
      1_000e6,
      address(AaveV3Ethereum.COLLECTOR),
      slippage
    );

    steward.withdrawV3andSwap(
      address(AaveV3Ethereum.POOL),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      slippage
    );

    assertLt(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceV3Before
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
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.InvalidZeroAmount.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      0,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      currentBalance - 999e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedToken() public {
    vm.startPrank(guardian);

    vm.expectRevert(IFinanceSteward.UnrecognizedToken.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_resvertsIf_invalidPriceFeedAnswer() public {
    address mockOracle = address(new MockOracle());

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, mockOracle);
    steward.setSwappableToken(
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      AaveV3EthereumAssets.AAVE_ORACLE
    );

    vm.startPrank(guardian);
    vm.expectRevert(IFinanceSteward.PriceFeedFailure.selector);
    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      100
    );
    vm.stopPrank();
  }

  function test_success() public {
    uint256 slippage = 100;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setSwappableToken(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);

    vm.startPrank(guardian);
    vm.expectEmit(true, true, true, true, address(steward.SWAPPER()));
    emit SwapRequested(
      steward.MILKMAN(),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      USDC_PRICE_FEED,
      AAVE_PRICE_FEED,
      1_000e6,
      address(AaveV3Ethereum.COLLECTOR),
      slippage
    );

    steward.tokenSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      slippage
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

    vm.expectRevert(IFinanceSteward.UnrecognizedReceiver.selector);
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

    vm.expectRevert(IFinanceSteward.ExceedsBalance.selector);
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.ExceedsBudget.selector, 1_000e6));
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertEq(IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).allowance(address(AaveV3Ethereum.COLLECTOR), alice), 0);

    vm.startPrank(guardian);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();

    assertEq(IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).allowance(address(AaveV3Ethereum.COLLECTOR), alice), 1_000e6);
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

    vm.expectRevert(IFinanceSteward.UnrecognizedReceiver.selector);
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

    vm.expectRevert(IFinanceSteward.ExceedsBalance.selector);
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance - 999e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.ExceedsBudget.selector, 1_000e6));
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    uint256 balance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);

    assertEq(IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balance - 1_000e6);
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

    vm.expectRevert(IFinanceSteward.InvalidDate.selector);
    steward.createStream(alice, data);

    data = IFinanceSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      1_000e6,
      block.timestamp,
      block.timestamp - 1
    );

    vm.expectRevert(IFinanceSteward.InvalidDate.selector);
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

    vm.expectRevert(IFinanceSteward.UnrecognizedReceiver.selector);
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

    vm.expectRevert(IFinanceSteward.ExceedsBalance.selector);
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.MinimumBalanceShield.selector, 1_000e6));
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

    vm.expectRevert(abi.encodeWithSelector(IFinanceSteward.ExceedsBudget.selector, 1_000e6));
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

    uint256 streamId = AaveV3Ethereum.COLLECTOR.getNextStreamId();

    vm.startPrank(guardian);
    steward.createStream(alice, data);
    vm.stopPrank();

    vm.warp(block.timestamp + 5 days);

    vm.startPrank(alice);
    AaveV3Ethereum.COLLECTOR.withdrawFromStream(streamId, 1);
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

contract Function_increaseBudget is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_success() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 1_000e6);
  }
}

contract Function_decreaseBudget is FinanceSteward_Test {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert('Ownable: caller is not the owner');
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_decreaseBudgetLessThanTotal() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 1_000e6);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 750e6);
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 250e6);

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 750e6);
    vm.stopPrank();
  }

  function test_success() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);
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

  function test_resvertsIf_missingPriceFeed() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IFinanceSteward.MissingPriceFeed.selector);
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, address(0));

    vm.stopPrank();
  }

  function test_resvertsIf_incompatibleOracleMissingImplementations() public {
    address mockOracle = address(new InvalidMockOracle());

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert();
    steward.setSwappableToken(AaveV3EthereumAssets.USDC_UNDERLYING, mockOracle);

    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit SwapApprovedToken(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
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

    vm.expectEmit(true, true, true, true, address(steward));
    emit ReceiverWhitelisted(alice);
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

    vm.expectEmit(true, true, true, true, address(steward));
    emit MinimumTokenBalanceUpdated(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.setMinimumBalanceShield(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }
}
