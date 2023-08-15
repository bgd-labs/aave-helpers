// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets} from 'aave-address-book/AaveV2Ethereum.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';

import {AaveCurator} from './AaveCurator.sol';

contract AaveCuratorTest is Test {
  event DepositedIntoV2(address indexed token, uint256 amount);
  event DepositedIntoV3(address indexed token, uint256 amount);
  event GuardianUpdated(address oldGuardian, address newGuardian);
  event SwapCanceled(address fromToken, address toToken, uint256 amount);
  event SwapRequested(address fromToken, address toToken, uint256 amount);
  event TokenUpdated(address indexed token, bool allowed);

  address public constant BAL80WETH20 = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;

  AaveCurator public curator;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17779177);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator = new AaveCurator();
    vm.stopPrank();
  }
}

contract Initialize is AaveCuratorTest {
  function test_revertsIf_alreadyInitialized() public {
    vm.expectRevert('Initializable: contract is already initialized');
    curator.initialize();
  }
}

contract TransferOwnership is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    curator.transferOwnership(makeAddr('new-admin'));
  }

  function test_successful() public {
    address newAdmin = makeAddr('new-admin');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.transferOwnership(newAdmin);
    vm.stopPrank();

    assertEq(newAdmin, curator.owner());
  }
}

contract UpdateGuardian is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.updateGuardian(makeAddr('new-admin'));
  }

  function test_successful() public {
    address newManager = makeAddr('new-admin');
    vm.expectEmit();
    emit GuardianUpdated(curator.guardian(), newManager);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.updateGuardian(newManager);
    vm.stopPrank();

    assertEq(newManager, curator.guardian());
  }
}

contract RemoveGuardian is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.updateGuardian(address(0));
  }

  function test_successful() public {
    vm.expectEmit();
    emit GuardianUpdated(curator.guardian(), address(0));
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.updateGuardian(address(0));
    vm.stopPrank();

    assertEq(address(0), curator.guardian());
  }
}

contract SetMilkman is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    curator.setMilkmanAddress(makeAddr('new-milkman'));
  }

  function test_revertsIf_invalid0xAddress() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    curator.setMilkmanAddress(address(0));
    vm.stopPrank();
  }

  function test_successful() public {
    address newMilkman = makeAddr('new-milkman');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setMilkmanAddress(newMilkman);
    vm.stopPrank();

    assertEq(curator.milkman(), newMilkman);
  }
}

contract SetChainlinkPriceChecker is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    curator.setChainlinkPriceChecker(makeAddr('new-chainlink'));
  }

  function test_revertsIf_invalid0xAddress() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    curator.setChainlinkPriceChecker(address(0));
    vm.stopPrank();
  }

  function test_successful() public {
    address newChainlink = makeAddr('new-milkman');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setChainlinkPriceChecker(newChainlink);
    vm.stopPrank();

    assertEq(curator.chainlinkPriceChecker(), newChainlink);
  }
}

contract AaveCuratorSwap is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    uint256 amount = 1_000e18;
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.swap(
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      amount,
      200
    );
  }

  function test_revertsIf_amountIsZero() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert(AaveCurator.InvalidAmount.selector);
    curator.swap(
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      0,
      200
    );
    vm.stopPrank();
  }

  function test_revertsIf_fromTokenNotAllowed() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert(AaveCurator.InvalidToken.selector);
    curator.swap(
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );
    vm.stopPrank();
  }

  function test_revertsIf_toTokenNotAllowed() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    vm.expectRevert(AaveCurator.InvalidToken.selector);
    curator.swap(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidRecipient() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV2EthereumAssets.USDC_UNDERLYING,
      AaveV2EthereumAssets.USDC_ORACLE,
      true
    );
    vm.expectRevert(AaveCurator.InvalidRecipient.selector);
    curator.swap(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      makeAddr('new-recipient'),
      1_000e18,
      200
    );
    vm.stopPrank();
  }

  function test_successful() public {
    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(curator), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV2EthereumAssets.USDC_UNDERLYING,
      AaveV2EthereumAssets.USDC_ORACLE,
      true
    );

    vm.expectEmit(true, true, true, true);
    emit SwapRequested(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      1_000e18
    );
    curator.swap(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );
    vm.stopPrank();
  }
}

contract CancelSwap is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    uint256 amount = 1_000e18;
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.cancelSwap(
      makeAddr('milkman-instance'),
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      amount,
      200
    );
  }

  function test_revertsIf_noMatchingTrade() public {
    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(curator), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV2EthereumAssets.USDC_UNDERLYING,
      AaveV2EthereumAssets.USDC_ORACLE,
      true
    );

    curator.swap(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );

    vm.expectRevert();
    curator.cancelSwap(
      makeAddr('not-milkman-instance'),
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );
    vm.stopPrank();
  }

  function test_successful_whatsapp() public {
    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(curator), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV2EthereumAssets.USDC_UNDERLYING,
      AaveV2EthereumAssets.USDC_ORACLE,
      true
    );

    vm.expectEmit(true, true, true, true);
    emit SwapRequested(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      1_000e18
    );
    curator.swap(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );

    vm.expectEmit();
    emit SwapCanceled(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      1_000e18
    );
    curator.cancelSwap(
      0xd0B587b7712a495499d45F761e234839d7E8D026, // Address generated by tests
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING,
      address(AaveV2Ethereum.COLLECTOR),
      1_000e18,
      200
    );
    vm.stopPrank();
  }
}

contract DepositIntoAaveV2 is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    uint256 amount = 1_000e18;
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.depositTokenIntoV2(AaveV2EthereumAssets.AAVE_UNDERLYING, amount);
  }

  function test_revertsIf_invalidToken() public {
    uint256 amount = 1_000e18;
    vm.expectRevert(AaveCurator.InvalidToken.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.depositTokenIntoV2(AaveV2EthereumAssets.AAVE_UNDERLYING, amount);
    vm.stopPrank();
  }

  function test_successful() public {
    uint256 amount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(curator), amount);

    uint256 balanceCollectorBefore = IERC20(AaveV2EthereumAssets.AAVE_A_TOKEN).balanceOf(
      address(AaveV2Ethereum.COLLECTOR)
    );

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), amount);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );

    vm.expectEmit();
    emit DepositedIntoV2(AaveV2EthereumAssets.AAVE_UNDERLYING, amount);
    curator.depositTokenIntoV2(AaveV2EthereumAssets.AAVE_UNDERLYING, amount);
    vm.stopPrank();

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
    assertGt(
      IERC20(AaveV2EthereumAssets.AAVE_A_TOKEN).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      balanceCollectorBefore
    );
  }
}

contract DepositIntoAaveV3 is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    uint256 amount = 1_000e18;
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.depositTokenIntoV3(AaveV3EthereumAssets.AAVE_UNDERLYING, amount);
  }

  function test_revertsIf_invalidToken() public {
    uint256 amount = 1_000e18;
    vm.expectRevert(AaveCurator.InvalidToken.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.depositTokenIntoV3(AaveV3EthereumAssets.AAVE_UNDERLYING, amount);
    vm.stopPrank();
  }

  function test_successful() public {
    uint256 amount = 1_000e18;

    deal(AaveV3EthereumAssets.AAVE_UNDERLYING, address(curator), amount);

    uint256 balanceCollectorBefore = IERC20(AaveV3EthereumAssets.AAVE_A_TOKEN).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), amount);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      AaveV3EthereumAssets.AAVE_ORACLE,
      true
    );

    vm.expectEmit();
    emit DepositedIntoV3(AaveV3EthereumAssets.AAVE_UNDERLYING, amount);
    curator.depositTokenIntoV3(AaveV3EthereumAssets.AAVE_UNDERLYING, amount);
    vm.stopPrank();

    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
    assertGt(
      IERC20(AaveV3EthereumAssets.AAVE_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceCollectorBefore
    );
  }
}

contract SetAllowedFromToken is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
  }

  function test_revertsIf_fromTokenIsAddressZero() public {
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(address(0), AaveV2EthereumAssets.AAVE_ORACLE, true);
    vm.stopPrank();
  }

  function test_revertsIf_oracleIsAddressZero() public {
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(AaveV2EthereumAssets.AAVE_UNDERLYING, address(0), true);
    vm.stopPrank();
  }

  function test_successful() public {
    assertFalse(curator.allowedFromTokens(AaveV2EthereumAssets.AAVE_UNDERLYING));
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit TokenUpdated(AaveV2EthereumAssets.AAVE_UNDERLYING, true);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    vm.stopPrank();

    assertTrue(curator.allowedFromTokens(AaveV2EthereumAssets.AAVE_UNDERLYING));
  }
}

contract SetAllowedToToken is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    curator.setAllowedToToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
  }

  function test_revertsIf_fromTokenIsAddressZero() public {
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedToToken(address(0), AaveV2EthereumAssets.AAVE_ORACLE, true);
    vm.stopPrank();
  }

  function test_revertsIf_oracleIsAddressZero() public {
    vm.expectRevert(AaveCurator.Invalid0xAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedToToken(AaveV2EthereumAssets.AAVE_UNDERLYING, address(0), true);
    vm.stopPrank();
  }

  function test_successful() public {
    assertFalse(curator.allowedToTokens(AaveV2EthereumAssets.AAVE_UNDERLYING));
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit TokenUpdated(AaveV2EthereumAssets.AAVE_UNDERLYING, true);
    curator.setAllowedToToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    vm.stopPrank();

    assertTrue(curator.allowedToTokens(AaveV2EthereumAssets.AAVE_UNDERLYING));
  }
}

contract WithdrawToCollector is AaveCuratorTest {
  function test_revertsIf_invalidCaller() public {
    address[] memory tokens = new address[](2);
    tokens[0] = AaveV2EthereumAssets.BAL_UNDERLYING;
    tokens[1] = AaveV2EthereumAssets.AAVE_UNDERLYING;

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    curator.withdrawToCollector(tokens);
  }

  function test_successful_allowedCaller() public {
    address AAVE_WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;
    address BAL_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    assertEq(IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(curator)), 0);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);

    uint256 balAmount = 1_000e18;
    uint256 aaveAmount = 1_000e18;

    vm.startPrank(BAL_WHALE);
    IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).transfer(address(curator), balAmount);
    vm.stopPrank();

    vm.startPrank(AAVE_WHALE);
    IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).transfer(address(curator), aaveAmount);
    vm.stopPrank();

    assertEq(IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(curator)), balAmount);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), aaveAmount);

    uint256 initialCollectorBalBalance = IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(
      address(AaveV2Ethereum.COLLECTOR)
    );
    uint256 initialCollectorUsdcBalance = IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(
      address(AaveV2Ethereum.COLLECTOR)
    );

    address newManager = makeAddr('new-manager');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.updateGuardian(newManager);
    vm.stopPrank();

    address[] memory tokens = new address[](2);
    tokens[0] = AaveV2EthereumAssets.BAL_UNDERLYING;
    tokens[1] = AaveV2EthereumAssets.AAVE_UNDERLYING;
    vm.startPrank(newManager);
    curator.withdrawToCollector(tokens);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorBalBalance + balAmount
    );
    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorUsdcBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
  }

  function test_successful_governanceCaller() public {
    address AAVE_WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;
    address BAL_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    assertEq(IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(curator)), 0);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);

    uint256 balAmount = 1_000e18;
    uint256 aaveAmount = 1_000e18;

    vm.startPrank(BAL_WHALE);
    IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).transfer(address(curator), balAmount);
    vm.stopPrank();

    vm.startPrank(AAVE_WHALE);
    IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).transfer(address(curator), aaveAmount);
    vm.stopPrank();

    assertEq(IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(curator)), balAmount);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), aaveAmount);

    uint256 initialCollectorBalBalance = IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(
      address(AaveV2Ethereum.COLLECTOR)
    );
    uint256 initialCollectorUsdcBalance = IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(
      address(AaveV2Ethereum.COLLECTOR)
    );

    address[] memory tokens = new address[](2);
    tokens[0] = AaveV2EthereumAssets.BAL_UNDERLYING;
    tokens[1] = AaveV2EthereumAssets.AAVE_UNDERLYING;
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.withdrawToCollector(tokens);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.BAL_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorBalBalance + balAmount
    );
    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorUsdcBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(curator)), 0);
  }
}

contract GetExpectedOut is AaveCuratorTest {
  function test_revertsIf_oracleNotSet() public {
    uint256 amount = 1e18;
    vm.expectRevert(AaveCurator.OracleNotSet.selector);
    curator.getExpectedOut(
      amount,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING
    );
  }

  function test_aaveToUsdc_withEthBasedOracles() public {
    /* This test is only to show that oracles with the same base
     * will return the correct value for trading, or at least very
     * close to USD based oracles. Nonetheless, ETH based oracles
     * should not be used. Please ensure only USD based oracles are
     * set for trading.
     * Using different bases in a swap can lead to destructive results.
     */

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV2EthereumAssets.USDC_UNDERLYING,
      AaveV2EthereumAssets.USDC_ORACLE,
      true
    );
    vm.stopPrank();

    uint256 amount = 1e18;
    uint256 expected = curator.getExpectedOut(
      amount,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      AaveV2EthereumAssets.USDC_UNDERLYING
    );

    // July 26, 2023 2:55PM EST AAVE/USD is around $71.20
    assertEq(expected / 1e4, 7121); // USDC is 6 decimals
  }

  function test_aaveToUsdc() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      AaveV3EthereumAssets.AAVE_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.USDC_ORACLE,
      true
    );
    vm.stopPrank();

    uint256 amount = 1e18;
    uint256 expected = curator.getExpectedOut(
      amount,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      AaveV3EthereumAssets.USDC_UNDERLYING
    );

    // July 26, 2023 2:55PM EST AAVE/USD is around $71.20
    assertEq(expected / 1e4, 7167); // USDC is 6 decimals
  }

  function test_ethToDai() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV3EthereumAssets.WETH_UNDERLYING,
      AaveV3EthereumAssets.WETH_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      AaveV3EthereumAssets.DAI_ORACLE,
      true
    );
    vm.stopPrank();

    uint256 amount = 1e18;
    uint256 expected = curator.getExpectedOut(
      amount,
      AaveV3EthereumAssets.WETH_UNDERLYING,
      AaveV3EthereumAssets.DAI_UNDERLYING
    );

    // July 26, 2023 2:55PM EST ETH/USD is around $1,870
    assertEq(expected / 1e18, 1870); // WETH is 18 decimals
  }

  function test_ethToBal() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    curator.setAllowedFromToken(
      AaveV3EthereumAssets.WETH_UNDERLYING,
      AaveV3EthereumAssets.WETH_ORACLE,
      true
    );
    curator.setAllowedToToken(
      AaveV3EthereumAssets.BAL_UNDERLYING,
      AaveV3EthereumAssets.BAL_ORACLE,
      true
    );
    vm.stopPrank();

    uint256 amount = 1e18;
    uint256 expected = curator.getExpectedOut(
      amount,
      AaveV3EthereumAssets.WETH_UNDERLYING,
      AaveV3EthereumAssets.BAL_UNDERLYING
    );

    // July 26, 2023 2:55PM EST ETH/USD is around $1,870, BAL/USD $4.50
    // Thus, ETH/BAL should be around 415 BAL tokens
    assertEq(expected / 1e18, 415); // WETH and BAL are 18 decimals
  }

  function test_balTo80BAL20WETH() public {
    uint256 amount = 100e18;
    uint256 expected = curator.getExpectedOut(
      amount,
      AaveV3EthereumAssets.BAL_UNDERLYING,
      BAL80WETH20
    );

    // July 25, 2023 10:15AM EST BAL/USD is around $4.50 B-80BAL-20WETH $12.50
    // Thus, BAL/BPT should be around 0.35 at 100 units traded, 35 units expected.
    assertEq(expected / 1e18, 35); // WETH and BAL are 18 decimals
  }
}
