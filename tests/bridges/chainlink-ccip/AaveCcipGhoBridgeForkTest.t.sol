// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console, Vm} from 'forge-std/Test.sol';
import {Strings} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {CCIPLocalSimulatorFork, Register, Internal} from '@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol';
import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import {IRouterClient} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol';

import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from 'aave-address-book/AaveV3Arbitrum.sol';

import {AaveCcipGhoBridge, IAaveCcipGhoBridge, CCIPReceiver} from 'src/bridges/chainlink-ccip/AaveCcipGhoBridge.sol';

interface ILockReleaseTokenPool {
  function getCurrentOutboundRateLimiterState(
    uint64 remoteChainSelector
  )
    external
    view
    returns (uint128 tokens, uint32 lastUpdated, bool isEnabled, uint128 capacity, uint128 rate);
  function getCurrentInboundRateLimiterState(
    uint64 remoteChainSelector
  )
    external
    view
    returns (uint128 tokens, uint32 lastUpdated, bool isEnabled, uint128 capacity, uint128 rate);
}

/// @dev forge test --match-path=tests/bridges/chainlink-ccip/AaveCcipGhoBridgeForkTest.t.sol -vvv
contract AaveCcipGhoBridgeTestBase is Test {
  uint64 public constant MAINNET_CHAIN_SELECTOR = 5009297550715157269;
  uint64 public constant ARBITRUM_CHAIN_SELECTOR = 4949039107694359620;

  CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
  uint256 public mainnetFork;
  uint256 public arbitrumFork;
  address public owner;
  address public alice;

  uint256 amountToSend = 1_000e18;
  AaveCcipGhoBridge mainnetBridge;
  AaveCcipGhoBridge arbitrumBridge;

  function setUp() public {
    arbitrumFork = vm.createFork(vm.rpcUrl('arbitrum'));
    mainnetFork = vm.createFork(vm.rpcUrl('mainnet'));

    vm.selectFork(arbitrumFork);

    owner = makeAddr('owner');
    alice = makeAddr('alice');

    ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
    vm.makePersistent(address(ccipLocalSimulatorFork));

    // arbitrum mainnet register config (https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet#arbitrum-mainnet)
    Register.NetworkDetails memory arbitrumNetworkDetails = Register.NetworkDetails({
      chainSelector: ARBITRUM_CHAIN_SELECTOR,
      routerAddress: 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8,
      linkAddress: 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4,
      wrappedNativeAddress: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
      ccipBnMAddress: 0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389,
      ccipLnMAddress: 0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB,
      rmnProxyAddress: 0xC311a21e6fEf769344EB1515588B9d535662a145,
      registryModuleOwnerCustomAddress: 0x818792C958Ac33C01c58D5026cEc91A86e9071d7,
      tokenAdminRegistryAddress: 0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E
    });
    ccipLocalSimulatorFork.setNetworkDetails(block.chainid, arbitrumNetworkDetails);

    arbitrumBridge = new AaveCcipGhoBridge(
      arbitrumNetworkDetails.routerAddress,
      AaveV3ArbitrumAssets.GHO_UNDERLYING,
      address(AaveV3Arbitrum.COLLECTOR),
      owner
    );

    vm.selectFork(mainnetFork);
    // mainnet register config (https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet#ethereum-mainnet)
    Register.NetworkDetails memory mainnetDetails = Register.NetworkDetails({
      chainSelector: MAINNET_CHAIN_SELECTOR,
      routerAddress: 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D,
      linkAddress: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
      wrappedNativeAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
      ccipBnMAddress: 0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389,
      ccipLnMAddress: 0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB,
      rmnProxyAddress: 0x411dE17f12D1A34ecC7F45f49844626267c75e81,
      registryModuleOwnerCustomAddress: 0x13022e3e6C77524308BD56AEd716E88311b2E533,
      tokenAdminRegistryAddress: 0xb22764f98dD05c789929716D677382Df22C05Cb6
    });
    ccipLocalSimulatorFork.setNetworkDetails(block.chainid, mainnetDetails);

    mainnetBridge = new AaveCcipGhoBridge(
      mainnetDetails.routerAddress,
      AaveV3EthereumAssets.GHO_UNDERLYING,
      address(AaveV3Ethereum.COLLECTOR),
      owner
    );

    vm.startPrank(alice);
    IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).approve(address(mainnetBridge), type(uint256).max);
    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    vm.startPrank(alice);
    IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).approve(address(arbitrumBridge), type(uint256).max);
    vm.stopPrank();
  }

  function _getMessageFromRecordedLogs() internal returns (Internal.EVM2EVMMessage memory message) {
    Vm.Log[] memory entries = vm.getRecordedLogs();
    uint256 length = entries.length;
    for (uint256 i; i < length; ++i) {
      if (entries[i].topics[0] == CCIPLocalSimulatorFork.CCIPSendRequested.selector) {
        message = abi.decode(entries[i].data, (Internal.EVM2EVMMessage));
      }
    }
    // emit event again because getRecordedLogs clear logs once called
    emit CCIPLocalSimulatorFork.CCIPSendRequested(message);
  }

  function _buildInvalidMessage() internal returns (Internal.EVM2EVMMessage memory) {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    vm.selectFork(mainnetFork);
    uint256 fee = mainnetBridge.quoteBridge(
      ARBITRUM_CHAIN_SELECTOR,
      amountToSend,
      0,
      AaveV3EthereumAssets.GHO_UNDERLYING
    );
    deal(AaveV3EthereumAssets.GHO_UNDERLYING, alice, amountToSend + fee);

    vm.startPrank(alice);
    mainnetBridge.bridge(
      ARBITRUM_CHAIN_SELECTOR,
      amountToSend,
      0,
      AaveV3EthereumAssets.GHO_UNDERLYING
    );

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);

    return message;
  }

  function assertMessage(
    Internal.EVM2EVMMessage memory internalMessage,
    Client.EVMTokenAmount[] memory invalidTokenTransfers
  ) internal {
    for (uint256 i = 0; i < internalMessage.tokenAmounts.length; ++i) {
      assertEq(internalMessage.tokenAmounts[i].amount, invalidTokenTransfers[i].amount);
    }
  }
}

contract BridgeTokenEthToArbWithGhoFee is AaveCcipGhoBridgeTestBase {
  address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

  function test_revertsIf_UnsupportedChain() external {
    vm.selectFork(mainnetFork);

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.UnsupportedChain.selector);
    mainnetBridge.bridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);
  }

  function test_revertsIf_NoBridgerRole() external {
    vm.selectFork(mainnetFork);
    vm.prank(owner);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(mainnetBridge.BRIDGER_ROLE()), 32)
      )
    );
    mainnetBridge.bridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);
  }

  function test_revertsIf_InvalidTransferAmount() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidTransferAmount.selector);
    mainnetBridge.bridge(ARBITRUM_CHAIN_SELECTOR, 0, 0, feeToken);
  }

  function test_revertsIf_DestinationNotConfigured() external {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    vm.selectFork(mainnetFork);
    uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);
    deal(AaveV3EthereumAssets.GHO_UNDERLYING, alice, amountToSend + fee);

    vm.startPrank(alice);
    vm.expectEmit(false, true, true, true, address(mainnetBridge));
    emit IAaveCcipGhoBridge.TransferIssued(
      bytes32(0),
      ARBITRUM_CHAIN_SELECTOR,
      alice,
      amountToSend
    );
    mainnetBridge.bridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    vm.expectEmit(true, false, false, false, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.ReceivedInvalidMessage(message.messageId);
    ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);

    assertTrue(arbitrumBridge.isInvalidMessage(message.messageId));
    Client.EVMTokenAmount[] memory invalidTokenTransfers = arbitrumBridge.getInvalidMessage(
      message.messageId
    );
    assertMessage(message, invalidTokenTransfers);
    vm.stopPrank();
  }

  function testFuzz_revertsIf_exceedLimit(uint256 amount) external {
    vm.selectFork(mainnetFork);
    // https://etherscan.io/address/0x06179f7C1be40863405f374E7f5F8806c728660A
    ILockReleaseTokenPool ghoPool = ILockReleaseTokenPool(
      0x06179f7C1be40863405f374E7f5F8806c728660A
    );
    (uint128 limit, , , , ) = ghoPool.getCurrentInboundRateLimiterState(ARBITRUM_CHAIN_SELECTOR);

    vm.assume(amount > limit && amount < 1e32); // made top limit to prevent arithmetic overflow

    vm.startPrank(owner);
    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);

    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));

    vm.stopPrank();

    vm.selectFork(mainnetFork);
    uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);
    deal(AaveV3EthereumAssets.GHO_UNDERLYING, alice, amount + fee);
    deal(alice, 100);

    vm.startPrank(alice);
    vm.expectRevert();
    mainnetBridge.bridge{value: 100}(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);
    vm.stopPrank();
  }

  function testFuzz_success(uint256 amount) external {
    vm.selectFork(mainnetFork);
    // https://etherscan.io/address/0x06179f7C1be40863405f374E7f5F8806c728660A
    ILockReleaseTokenPool ghoPool = ILockReleaseTokenPool(
      0x06179f7C1be40863405f374E7f5F8806c728660A
    );
    (uint128 limit, , , , ) = ghoPool.getCurrentInboundRateLimiterState(ARBITRUM_CHAIN_SELECTOR);

    vm.assume(amount > 0 && amount <= limit);
    vm.selectFork(arbitrumFork);

    uint256 beforeBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Arbitrum.COLLECTOR)
    );

    vm.startPrank(owner);
    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);

    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));

    vm.stopPrank();

    vm.selectFork(mainnetFork);
    uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);
    deal(AaveV3EthereumAssets.GHO_UNDERLYING, alice, amount + fee);
    deal(alice, 100);

    vm.startPrank(alice);
    vm.expectEmit(false, true, true, true, address(mainnetBridge));
    emit IAaveCcipGhoBridge.TransferIssued(bytes32(0), ARBITRUM_CHAIN_SELECTOR, alice, amount);
    mainnetBridge.bridge{value: 100}(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    vm.expectEmit(true, true, false, true, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.TransferFinished(
      message.messageId,
      address(AaveV3Arbitrum.COLLECTOR),
      amount
    );
    ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);
    uint256 afterBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Arbitrum.COLLECTOR)
    );
    assertEq(afterBalance, beforeBalance + amount, 'Bridged amount not updated correctly');
    vm.stopPrank();
  }
}

contract BridgeTokenArbToEthWithNativeFee is AaveCcipGhoBridgeTestBase {
  address public feeToken = address(0);

  function test_revertsIf_UnsupportedChain() external {
    vm.selectFork(arbitrumFork);

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.UnsupportedChain.selector);
    arbitrumBridge.bridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
  }

  function test_revertsIf_NoBridgerRole() external {
    vm.selectFork(arbitrumFork);
    vm.prank(owner);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));

    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(arbitrumBridge.BRIDGER_ROLE()), 32)
      )
    );
    arbitrumBridge.bridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
  }

  function test_revertsIf_InvalidTransferAmount() external {
    vm.selectFork(arbitrumFork);
    vm.startPrank(owner);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidTransferAmount.selector);
    arbitrumBridge.bridge(MAINNET_CHAIN_SELECTOR, 0, 0, feeToken);
  }

  function test_revertsIf_InsufficientNativeFee() external {
    vm.startPrank(owner);
    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amountToSend);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InsufficientNativeFee.selector);
    arbitrumBridge.bridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
    vm.stopPrank();
  }

  function test_revertsIf_InvalidFeeToken() external {
    address invalidFeeToken = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4; // LINK token
    vm.startPrank(owner);
    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(
      MAINNET_CHAIN_SELECTOR,
      amountToSend,
      0,
      address(0) // use address(0) to estimate to escape exception of quote function
    );
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amountToSend);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidFeeToken.selector);
    arbitrumBridge.bridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, invalidFeeToken);
    vm.stopPrank();
  }

  function test_revertsIf_DestinationNotConfigured() external {
    vm.startPrank(owner);
    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amountToSend);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectEmit(false, true, true, true, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.TransferIssued(bytes32(0), MAINNET_CHAIN_SELECTOR, alice, amountToSend);
    arbitrumBridge.bridge{value: fee}(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    vm.expectEmit(true, false, false, false, address(mainnetBridge));
    emit IAaveCcipGhoBridge.ReceivedInvalidMessage(message.messageId);
    ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);

    assertTrue(mainnetBridge.isInvalidMessage(message.messageId));
    Client.EVMTokenAmount[] memory invalidTokenTransfers = mainnetBridge.getInvalidMessage(
      message.messageId
    );
    assertMessage(message, invalidTokenTransfers);
    vm.stopPrank();
  }

  function test_success_customGasLimit() external {
    vm.selectFork(mainnetFork);

    uint256 beforeBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.startPrank(owner);
    vm.selectFork(arbitrumFork);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(
      MAINNET_CHAIN_SELECTOR,
      amountToSend,
      300000,
      feeToken
    );
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amountToSend);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectEmit(false, true, true, true, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.TransferIssued(bytes32(0), MAINNET_CHAIN_SELECTOR, alice, amountToSend);
    arbitrumBridge.bridge{value: fee}(MAINNET_CHAIN_SELECTOR, amountToSend, 300000, feeToken);

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    vm.expectEmit(true, true, false, true, address(mainnetBridge));
    emit IAaveCcipGhoBridge.TransferFinished(
      message.messageId,
      address(AaveV3Ethereum.COLLECTOR),
      amountToSend
    );
    ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);
    uint256 afterBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    assertEq(afterBalance, beforeBalance + amountToSend, 'Bridged amount not updated correctly');
    vm.stopPrank();
  }

  function testFuzz_revertsIf_exceedLimit(uint256 amount) external {
    vm.selectFork(arbitrumFork);
    // https://arbiscan.io/address/0xB94Ab28c6869466a46a42abA834ca2B3cECCA5eB
    ILockReleaseTokenPool ghoPool = ILockReleaseTokenPool(
      0xB94Ab28c6869466a46a42abA834ca2B3cECCA5eB
    );
    (uint128 limit, , , , ) = ghoPool.getCurrentOutboundRateLimiterState(MAINNET_CHAIN_SELECTOR);

    vm.assume(amount > limit && amount < 1e32); // made top limit to prevent arithmetic overflow

    vm.startPrank(owner);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amount, 300000, feeToken);
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amount);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectRevert();
    arbitrumBridge.bridge{value: fee}(MAINNET_CHAIN_SELECTOR, amount, 300000, feeToken);
    vm.stopPrank();
  }

  function testFuzz_success(uint256 amount) external {
    vm.selectFork(arbitrumFork);
    // https://arbiscan.io/address/0xB94Ab28c6869466a46a42abA834ca2B3cECCA5eB
    ILockReleaseTokenPool ghoPool = ILockReleaseTokenPool(
      0xB94Ab28c6869466a46a42abA834ca2B3cECCA5eB
    );
    (uint128 limit, , , , ) = ghoPool.getCurrentOutboundRateLimiterState(MAINNET_CHAIN_SELECTOR);

    vm.assume(amount > 0 && amount <= limit);
    vm.selectFork(mainnetFork);

    uint256 beforeBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );

    vm.selectFork(arbitrumFork);
    vm.startPrank(owner);
    arbitrumBridge.setDestinationBridge(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
    arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), alice);

    vm.selectFork(mainnetFork);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

    vm.stopPrank();

    vm.selectFork(arbitrumFork);
    uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amount, 300000, feeToken);
    deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, alice, amount);
    deal(alice, fee);

    vm.startPrank(alice);
    vm.expectEmit(false, true, true, true, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.TransferIssued(bytes32(0), MAINNET_CHAIN_SELECTOR, alice, amount);
    arbitrumBridge.bridge{value: fee}(MAINNET_CHAIN_SELECTOR, amount, 300000, feeToken);

    Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

    vm.expectEmit(true, true, false, true, address(mainnetBridge));
    emit IAaveCcipGhoBridge.TransferFinished(
      message.messageId,
      address(AaveV3Ethereum.COLLECTOR),
      amount
    );
    ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);
    uint256 afterBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Ethereum.COLLECTOR)
    );
    assertEq(afterBalance, beforeBalance + amount, 'Bridged amount not updated correctly');
    vm.stopPrank();
  }
}

contract HandleInvalidMessageTest is AaveCcipGhoBridgeTestBase {
  address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

  function test_revertIf_NotOwner() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(alice);

    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(mainnetBridge.DEFAULT_ADMIN_ROLE()), 32)
      )
    );
    mainnetBridge.handleInvalidMessage(bytes32(0));
    vm.stopPrank();
  }

  function test_revertIf_MessageNotFound() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);

    vm.expectRevert(IAaveCcipGhoBridge.MessageNotFound.selector);
    mainnetBridge.handleInvalidMessage(bytes32(0));
    vm.stopPrank();
  }

  function test_success() external {
    Internal.EVM2EVMMessage memory message = _buildInvalidMessage();

    vm.selectFork(arbitrumFork);
    vm.startPrank(owner);

    uint256 balanceBefore = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Arbitrum.COLLECTOR)
    );

    vm.expectEmit(true, false, false, false, address(arbitrumBridge));
    emit IAaveCcipGhoBridge.HandledInvalidMessage(message.messageId);
    arbitrumBridge.handleInvalidMessage(message.messageId);

    uint256 balanceAfter = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(
      address(AaveV3Arbitrum.COLLECTOR)
    );

    assertEq(balanceAfter, balanceBefore + amountToSend);

    vm.stopPrank();
  }
}

contract SetDestinationBridgeTest is AaveCcipGhoBridgeTestBase {
  function test_revertIf_NotOwner() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(alice);

    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(mainnetBridge.DEFAULT_ADMIN_ROLE()), 32)
      )
    );
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    vm.stopPrank();
  }

  function test_success() external {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);

    vm.expectEmit(address(mainnetBridge));
    emit IAaveCcipGhoBridge.DestinationUpdated(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

    assertEq(
      mainnetBridge.bridges(ARBITRUM_CHAIN_SELECTOR),
      address(arbitrumBridge),
      'Destination bridge not set correctly in the mapping'
    );
    vm.stopPrank();
  }
}

contract ProcessMessageTest is AaveCcipGhoBridgeTestBase {
  function test_reverts_OnlySelf() public {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(IAaveCcipGhoBridge.OnlySelf.selector);
    mainnetBridge.processMessage(message);

    vm.stopPrank();
  }
}

contract CcipReceiveTest is AaveCcipGhoBridgeTestBase {
  function test_reverts_InvalidRouter() public {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, owner));
    mainnetBridge.ccipReceive(message);

    vm.stopPrank();
  }

  function test_successWith_ReceivedInvalidMessage() public {
    vm.startPrank(owner);
    vm.selectFork(mainnetFork);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });
    vm.stopPrank();

    vm.startPrank(mainnetBridge.ROUTER());

    vm.expectEmit(address(mainnetBridge));
    emit IAaveCcipGhoBridge.ReceivedInvalidMessage(bytes32(0));
    mainnetBridge.ccipReceive(message);

    vm.stopPrank();
  }
}

contract QuoteTransferTest is AaveCcipGhoBridgeTestBase {
  address public feeToken = address(0);

  function test_revertsIf_UnsupportedChain() external {
    vm.selectFork(mainnetFork);

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.UnsupportedChain.selector);
    mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);
  }

  function test_revertsIf_InvalidTransferAmount() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidTransferAmount.selector);
    mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, 0, 0, feeToken);
  }

  function test_revertsIf_InvalidFeeToken() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidFeeToken.selector);
    mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, address(1));
  }

  function test_success() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);
    mainnetBridge.setDestinationBridge(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amountToSend, 0, feeToken);

    assertGt(fee, 0);
  }
}

contract RescuableTest is AaveCcipGhoBridgeTestBase {
  uint256 amount = 1e18;

  function test_assert() external {
    vm.selectFork(mainnetFork);
    deal(AaveV3EthereumAssets.GHO_UNDERLYING, address(mainnetBridge), amount);
    assertEq(mainnetBridge.whoCanRescue(), owner);
    assertEq(mainnetBridge.maxRescue(AaveV3EthereumAssets.GHO_UNDERLYING), amount);
  }
}

contract GetInvalidMessage is AaveCcipGhoBridgeTestBase {
  address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

  function test_revertIf_MessageNotFound() external {
    vm.selectFork(mainnetFork);
    vm.startPrank(owner);

    vm.expectRevert(IAaveCcipGhoBridge.MessageNotFound.selector);
    mainnetBridge.getInvalidMessage(bytes32(0));
    vm.stopPrank();
  }

  function test_success() external {
    Internal.EVM2EVMMessage memory message = _buildInvalidMessage();

    vm.selectFork(arbitrumFork);
    vm.startPrank(owner);

    arbitrumBridge.getInvalidMessage(message.messageId);

    vm.stopPrank();
  }
}
