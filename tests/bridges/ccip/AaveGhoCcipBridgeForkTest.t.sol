// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {Strings} from "aave-v3-origin/contracts/dependencies/openzeppelin/contracts/Strings.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {GhoArbitrum} from "aave-address-book/GhoArbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {IRescuable} from "solidity-utils/contracts/utils/interfaces/IRescuable.sol";

import {CCIPLocalSimulatorFork, Register, Internal} from "./mocks/CCIPLocalSimulatorFork.sol";
import {Constants} from "./Constants.sol";
import {Client} from "src/bridges/ccip/libraries/Client.sol";
import {CCIPReceiver} from "src/bridges/ccip/CCIPReceiver.sol";
import {IGhoToken} from "./IGhoToken.sol";
import {IRouterClient} from "src/bridges/ccip/interfaces/IRouterClient.sol";
import {ITokenPool} from "src/bridges/ccip/interfaces/ITokenPool.sol";
import {AaveGhoCcipBridge} from "src/bridges/ccip/AaveGhoCcipBridge.sol";
import {IAaveGhoCcipBridge} from "src/bridges/ccip/interfaces/IAaveGhoCcipBridge.sol";

contract AaveGhoCcipBridgeForkTestBase is Test, Constants {
    /// @dev Error from CCIP
    error NotAFeeToken(address token);

    uint256 public constant AMOUNT_TO_SEND = 1_000_000 ether;
    uint256 public mainnetFork;
    uint256 public arbitrumFork;
    address public admin = makeAddr("admin");
    address public facilitator = makeAddr("facilitator");

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    AaveGhoCcipBridge mainnetBridge;
    AaveGhoCcipBridge arbitrumBridge;

    function setUp() public {
        mainnetFork = vm.createFork(vm.rpcUrl("mainnet"), 22637440);
        arbitrumFork = vm.createSelectFork(vm.rpcUrl("arbitrum"), 344116880);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails memory arbitrumNetworkDetails = Register.NetworkDetails({
            chainSelector: ARBITRUM_CHAIN_SELECTOR,
            routerAddress: ARBITRUM_ROUTER,
            linkAddress: ARBITRUM_LINK,
            wrappedNativeAddress: ARBITRUM_WETH,
            ccipBnMAddress: 0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389,
            ccipLnMAddress: 0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB,
            rmnProxyAddress: ARBITRUM_RMN_PROXY,
            registryModuleOwnerCustomAddress: ARBITRUM_REGISTRY_OWNER,
            tokenAdminRegistryAddress: ARBITRUM_TOKEN_ADMIN
        });
        ccipLocalSimulatorFork.setNetworkDetails(block.chainid, arbitrumNetworkDetails);

        arbitrumBridge = new AaveGhoCcipBridge(
            arbitrumNetworkDetails.routerAddress,
            AaveV3ArbitrumAssets.GHO_UNDERLYING,
            address(AaveV3Arbitrum.COLLECTOR),
            admin
        );

        vm.startPrank(facilitator);
        IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).approve(address(arbitrumBridge), type(uint256).max);
        vm.stopPrank();

        vm.selectFork(mainnetFork);
        Register.NetworkDetails memory mainnetDetails = Register.NetworkDetails({
            chainSelector: MAINNET_CHAIN_SELECTOR,
            routerAddress: MAINNET_ROUTER,
            linkAddress: MAINNET_LINK,
            wrappedNativeAddress: MAINNET_WETH,
            ccipBnMAddress: 0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389,
            ccipLnMAddress: 0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB,
            rmnProxyAddress: MAINNET_RMN_PROXY,
            registryModuleOwnerCustomAddress: MAINNET_REGISTRY_OWNER,
            tokenAdminRegistryAddress: MAINNET_TOKEN_ADMIN
        });
        ccipLocalSimulatorFork.setNetworkDetails(block.chainid, mainnetDetails);

        mainnetBridge = new AaveGhoCcipBridge(
            mainnetDetails.routerAddress, AaveV3EthereumAssets.GHO_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), admin
        );

        vm.startPrank(admin);
        mainnetBridge.setDestinationChain(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
        mainnetBridge.grantRole(mainnetBridge.BRIDGER_ROLE(), facilitator);
        vm.stopPrank();

        vm.startPrank(facilitator);
        IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).approve(address(mainnetBridge), type(uint256).max);
        vm.stopPrank();

        vm.selectFork(arbitrumFork);
        vm.startPrank(admin);
        arbitrumBridge.setDestinationChain(MAINNET_CHAIN_SELECTOR, address(mainnetBridge));
        arbitrumBridge.grantRole(arbitrumBridge.BRIDGER_ROLE(), facilitator);
        vm.stopPrank();
    }

    function _getMessageFromRecordedLogs() internal returns (Internal.EVM2EVMMessage memory) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Internal.EVM2EVMMessage memory message;
        uint256 length = entries.length;
        for (uint256 i; i < length; ++i) {
            if (entries[i].topics[0] == CCIPLocalSimulatorFork.CCIPSendRequested.selector) {
                message = abi.decode(entries[i].data, (Internal.EVM2EVMMessage));
            }
        }

        // Emit event again because getRecordedLogs clears logs after call
        emit CCIPLocalSimulatorFork.CCIPSendRequested(message);

        return message;
    }

    function _buildInvalidMessage() internal returns (Internal.EVM2EVMMessage memory) {
        vm.startPrank(admin);
        vm.selectFork(arbitrumFork);
        arbitrumBridge.removeDestinationChain(MAINNET_CHAIN_SELECTOR);
        vm.stopPrank();

        vm.selectFork(mainnetFork);
        uint256 fee =
            mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, AaveV3EthereumAssets.GHO_UNDERLYING);
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, facilitator, AMOUNT_TO_SEND + fee);

        vm.startPrank(facilitator);
        mainnetBridge.send(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, AaveV3EthereumAssets.GHO_UNDERLYING);
        vm.stopPrank();

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);

        return message;
    }

    function assertMessage(
        Internal.EVM2EVMMessage memory internalMessage,
        Client.EVMTokenAmount[] memory invalidTokenTransfers
    ) internal pure {
        for (uint256 i = 0; i < internalMessage.tokenAmounts.length; ++i) {
            assertEq(internalMessage.tokenAmounts[i].amount, invalidTokenTransfers[i].amount);
        }
    }
}

contract SendMainnetToArbitrum is AaveGhoCcipBridgeForkTestBase {
    address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

    function test_revertsIf_unsupportedChain() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.UnsupportedChain.selector);
        mainnetBridge.send(BLAST_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
    }

    function test_revertsIf_callerNoBridgerRole() public {
        vm.selectFork(mainnetFork);
        address caller = makeAddr("random-caller");
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(caller), 20),
                " is missing role ",
                Strings.toHexString(uint256(mainnetBridge.BRIDGER_ROLE()), 32)
            )
        );
        mainnetBridge.send(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
    }

    function test_revertsIf_invalidTransferAmount() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.InvalidZeroAmount.selector);
        mainnetBridge.send(ARBITRUM_CHAIN_SELECTOR, 0, 0, feeToken);
    }

    function test_revertsIf_sourceChainNotConfigured() public {
        vm.startPrank(admin);
        vm.selectFork(arbitrumFork);
        arbitrumBridge.removeDestinationChain(MAINNET_CHAIN_SELECTOR);
        vm.stopPrank();

        vm.selectFork(mainnetFork);
        uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, facilitator, AMOUNT_TO_SEND + fee);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), ARBITRUM_CHAIN_SELECTOR, facilitator, AMOUNT_TO_SEND);
        mainnetBridge.send(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, false, false, false, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.FailedToFinalizeBridge(message.messageId, bytes(hex"5ea23900"));
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);

        Client.EVMTokenAmount[] memory messageData = arbitrumBridge.getInvalidMessage(message.messageId);
        assertTrue(messageData.length > 0);
        Client.EVMTokenAmount[] memory invalidTokenTransfers = arbitrumBridge.getInvalidMessage(message.messageId);
        assertMessage(message, invalidTokenTransfers);
        vm.stopPrank();
    }

    function testFuzz_revertsIf_rateLimitExceeded(uint256 amount) public {
        vm.selectFork(mainnetFork);
        uint128 limit = mainnetBridge.getRateLimit(ARBITRUM_CHAIN_SELECTOR);

        // vm.assume(amount > limit && amount < 1e32); // made top limit to prevent arithmetic overflow
        amount = bound(amount, limit + 1, 1e32 - 1);
        uint256 fee = 1 ether; // set static fee because quoteBridge reverts if amount exceed limit
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, facilitator, amount + fee);
        deal(facilitator, 100);

        vm.startPrank(facilitator);
        vm.expectRevert(abi.encodeWithSelector(IAaveGhoCcipBridge.RateLimitExceeded.selector, limit));
        mainnetBridge.send{value: 100}(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);
        vm.stopPrank();
    }

    function test_successful_fuzz(uint256 amount) public {
        vm.selectFork(mainnetFork);
        uint128 limit = mainnetBridge.getRateLimit(ARBITRUM_CHAIN_SELECTOR);

        vm.assume(amount > 0 && amount <= limit);
        vm.selectFork(arbitrumFork);

        uint256 beforeBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        vm.selectFork(mainnetFork);
        uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, facilitator, amount + fee);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), ARBITRUM_CHAIN_SELECTOR, facilitator, amount);
        mainnetBridge.send(ARBITRUM_CHAIN_SELECTOR, amount, 0, feeToken);

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, true, false, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeFinalized(message.messageId, address(AaveV3Arbitrum.COLLECTOR), amount);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);
        uint256 afterBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));
        assertEq(afterBalance, beforeBalance + amount, "Bridged amount not updated correctly");
        vm.stopPrank();
    }

    function test_successful_payWithEth(uint256 amount) public {
        vm.selectFork(mainnetFork);
        uint128 limit = mainnetBridge.getRateLimit(ARBITRUM_CHAIN_SELECTOR);

        vm.assume(amount > 0 && amount <= limit);
        vm.selectFork(arbitrumFork);

        uint256 beforeBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        vm.selectFork(mainnetFork);
        uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, amount, 0, address(0));
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, facilitator, amount);
        deal(facilitator, 100 ether);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), ARBITRUM_CHAIN_SELECTOR, facilitator, amount);
        mainnetBridge.send{value: fee}(ARBITRUM_CHAIN_SELECTOR, amount, 0, address(0));

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, true, false, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeFinalized(message.messageId, address(AaveV3Arbitrum.COLLECTOR), amount);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumFork);
        uint256 afterBalance = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));
        assertEq(afterBalance, beforeBalance + amount, "Bridged amount not updated correctly");
        vm.stopPrank();
    }
}

contract SendArbitrumToMainnet is AaveGhoCcipBridgeForkTestBase {
    address public feeToken = AaveV3ArbitrumAssets.GHO_UNDERLYING;

    function test_revertsIf_unsupportedChain() public {
        vm.selectFork(arbitrumFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.UnsupportedChain.selector);
        arbitrumBridge.send(BLAST_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
    }

    function test_revertsIf_callerNoBridgerRole() public {
        vm.selectFork(arbitrumFork);
        address caller = makeAddr("random-caller");
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(caller), 20),
                " is missing role ",
                Strings.toHexString(uint256(arbitrumBridge.BRIDGER_ROLE()), 32)
            )
        );
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
    }

    function test_revertsIf_invalidTransferAmount() public {
        vm.selectFork(arbitrumFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.InvalidZeroAmount.selector);
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, 0, 0, feeToken);
    }

    function test_revertsIf_insufficientNativeFee() public {
        vm.selectFork(arbitrumFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.InsufficientFee.selector);
        arbitrumBridge.send{value: 0}(MAINNET_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, address(0));
        vm.stopPrank();
    }

    function test_revertsIf_invalidFeeToken() public {
        address invalidFeeToken = makeAddr("new erc20");
        vm.selectFork(arbitrumFork);
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, AMOUNT_TO_SEND);

        vm.startPrank(facilitator);
        vm.expectRevert(abi.encodeWithSelector(NotAFeeToken.selector, invalidFeeToken));
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, invalidFeeToken);
        vm.stopPrank();
    }

    function test_revertsIf_sourceChainNotConfigured() public {
        vm.startPrank(admin);
        vm.selectFork(mainnetFork);
        mainnetBridge.removeDestinationChain(ARBITRUM_CHAIN_SELECTOR);
        vm.stopPrank();

        vm.selectFork(arbitrumFork);
        uint256 amountToSend = 1_000 ether;
        uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, AMOUNT_TO_SEND + fee);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), MAINNET_CHAIN_SELECTOR, facilitator, amountToSend);
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, amountToSend, 0, feeToken);

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, false, false, false, address(mainnetBridge));
        emit IAaveGhoCcipBridge.FailedToFinalizeBridge(message.messageId, bytes(hex"5ea23900"));
        ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);

        Client.EVMTokenAmount[] memory messageData = mainnetBridge.getInvalidMessage(message.messageId);
        assertTrue(messageData.length > 0);
        Client.EVMTokenAmount[] memory invalidTokenTransfers = mainnetBridge.getInvalidMessage(message.messageId);
        assertMessage(message, invalidTokenTransfers);
        vm.stopPrank();
    }

    function test_successful_customGasLimit() public {
        vm.selectFork(mainnetFork);
        uint256 beforeBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));
        uint256 customGasLimit = 300_000;

        vm.selectFork(arbitrumFork);
        uint256 amountToSend = 1_000 ether;
        uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amountToSend, customGasLimit, feeToken);
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, amountToSend + fee);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), MAINNET_CHAIN_SELECTOR, facilitator, amountToSend);
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, amountToSend, customGasLimit, feeToken);

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, true, false, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeFinalized(message.messageId, address(AaveV3Ethereum.COLLECTOR), amountToSend);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);
        uint256 afterBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));
        assertEq(afterBalance, beforeBalance + amountToSend, "Bridged amount not updated correctly");
        vm.stopPrank();
    }

    function test_revertsIf_fuzzRateLimitExceeded(uint256 amount) public {
        vm.selectFork(arbitrumFork);
        uint128 limit = arbitrumBridge.getRateLimit(MAINNET_CHAIN_SELECTOR);
        (uint256 bucket, uint256 level) =
            IGhoToken(AaveV3ArbitrumAssets.GHO_UNDERLYING).getFacilitatorBucket(GhoArbitrum.GHO_CCIP_TOKEN_POOL);

        vm.assume(amount > limit && amount < bucket - level); // made top limit to prevent arithmetic overflow
        vm.prank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
        ITokenPool(GhoArbitrum.GHO_CCIP_TOKEN_POOL).directMint(facilitator, amount); // Mint amount so enough GHO is available on Arbitrum

        uint256 fee = 1 ether; // set static fee to avoid reverts of quote bridge
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, amount + fee);

        vm.startPrank(facilitator);
        vm.expectRevert(abi.encodeWithSelector(IAaveGhoCcipBridge.RateLimitExceeded.selector, limit));
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, amount, 300_000, feeToken);
        vm.stopPrank();
    }

    function test_successful_fuzz(uint256 amount) public {
        vm.selectFork(mainnetFork);
        uint256 beforeBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.selectFork(arbitrumFork);
        uint128 limit = arbitrumBridge.getRateLimit(MAINNET_CHAIN_SELECTOR);
        vm.assume(amount > 0 && amount <= limit);

        vm.prank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
        ITokenPool(GhoArbitrum.GHO_CCIP_TOKEN_POOL).directMint(facilitator, amount); // Mint amount so enough GHO is available on Arbitrum

        uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amount, 300_000, feeToken);
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, amount + fee);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), MAINNET_CHAIN_SELECTOR, facilitator, amount);
        arbitrumBridge.send(MAINNET_CHAIN_SELECTOR, amount, 300_000, feeToken);

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, true, false, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeFinalized(message.messageId, address(AaveV3Ethereum.COLLECTOR), amount);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);
        uint256 afterBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));
        assertEq(afterBalance, beforeBalance + amount, "Bridged amount not updated correctly");
        vm.stopPrank();
    }

    function test_successful_payWithEth(uint256 amount) public {
        vm.selectFork(mainnetFork);
        uint256 beforeBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.selectFork(arbitrumFork);
        uint128 limit = arbitrumBridge.getRateLimit(MAINNET_CHAIN_SELECTOR);
        vm.assume(amount > 0 && amount <= limit);

        vm.prank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
        ITokenPool(GhoArbitrum.GHO_CCIP_TOKEN_POOL).directMint(facilitator, amount); // Mint amount so enough GHO is available on Arbitrum

        uint256 fee = arbitrumBridge.quoteBridge(MAINNET_CHAIN_SELECTOR, amount, 0, address(0));
        deal(AaveV3ArbitrumAssets.GHO_UNDERLYING, facilitator, amount);
        deal(facilitator, 100 ether);

        vm.startPrank(facilitator);
        vm.expectEmit(false, true, true, true, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.BridgeInitiated(bytes32(0), MAINNET_CHAIN_SELECTOR, facilitator, amount);
        arbitrumBridge.send{value: fee}(MAINNET_CHAIN_SELECTOR, amount, 0, address(0));

        Internal.EVM2EVMMessage memory message = _getMessageFromRecordedLogs();

        vm.expectEmit(true, true, false, true, address(mainnetBridge));
        emit IAaveGhoCcipBridge.BridgeFinalized(message.messageId, address(AaveV3Ethereum.COLLECTOR), amount);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(mainnetFork);
        uint256 afterBalance = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));
        assertEq(afterBalance, beforeBalance + amount, "Bridged amount not updated correctly");
        vm.stopPrank();
    }
}

contract RecoverFailedMessageTokensTest is AaveGhoCcipBridgeForkTestBase {
    address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

    function test_revertIf_callerNotOwner() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(facilitator), 20),
                " is missing role ",
                Strings.toHexString(uint256(mainnetBridge.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        mainnetBridge.recoverFailedMessageTokens(bytes32(0));
        vm.stopPrank();
    }

    function test_revertIf_messageNotFound() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        vm.expectRevert(IAaveGhoCcipBridge.MessageNotFound.selector);
        mainnetBridge.recoverFailedMessageTokens(bytes32(0));
        vm.stopPrank();
    }

    function test_successful() public {
        Internal.EVM2EVMMessage memory message = _buildInvalidMessage();

        vm.selectFork(arbitrumFork);
        uint256 balanceBefore = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        vm.startPrank(admin);
        vm.expectEmit(true, false, false, false, address(arbitrumBridge));
        emit IAaveGhoCcipBridge.RecoveredInvalidMessage(message.messageId);
        arbitrumBridge.recoverFailedMessageTokens(message.messageId);

        uint256 balanceAfter = IERC20(AaveV3ArbitrumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        assertEq(balanceAfter, balanceBefore + AMOUNT_TO_SEND);

        vm.stopPrank();
    }
}

contract SetDestinationChainTest is AaveGhoCcipBridgeForkTestBase {
    function test_revertIf_callerNotOwner() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(facilitator), 20),
                " is missing role ",
                Strings.toHexString(uint256(mainnetBridge.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        mainnetBridge.setDestinationChain(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
    }

    function test_successful() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        vm.expectEmit(address(mainnetBridge));
        emit IAaveGhoCcipBridge.DestinationChainSet(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
        mainnetBridge.setDestinationChain(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

        assertEq(
            mainnetBridge.destinations(ARBITRUM_CHAIN_SELECTOR),
            address(arbitrumBridge),
            "Destination bridge not set correctly in the mapping"
        );
    }
}

contract RemoveDestinationChainTest is AaveGhoCcipBridgeForkTestBase {
    function test_revertIf_callerNotOwner() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(facilitator), 20),
                " is missing role ",
                Strings.toHexString(uint256(mainnetBridge.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        mainnetBridge.removeDestinationChain(ARBITRUM_CHAIN_SELECTOR);
    }

    function test_successful() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        vm.expectEmit(address(mainnetBridge));
        emit IAaveGhoCcipBridge.DestinationChainSet(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));
        mainnetBridge.setDestinationChain(ARBITRUM_CHAIN_SELECTOR, address(arbitrumBridge));

        assertEq(
            mainnetBridge.destinations(ARBITRUM_CHAIN_SELECTOR),
            address(arbitrumBridge),
            "Destination bridge not set correctly in the mapping"
        );

        vm.expectEmit(address(mainnetBridge));
        emit IAaveGhoCcipBridge.DestinationChainRemoved(ARBITRUM_CHAIN_SELECTOR);
        mainnetBridge.removeDestinationChain(ARBITRUM_CHAIN_SELECTOR);

        assertEq(
            mainnetBridge.destinations(ARBITRUM_CHAIN_SELECTOR),
            address(0),
            "Destination bridge not removed correctly in the mapping"
        );
    }
}

contract ProcessMessageTest is AaveGhoCcipBridgeForkTestBase {
    function test_revertsIf_callerNotSelf() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        // build dummy message for test
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
            sender: abi.encode(address(0)),
            data: "",
            destTokenAmounts: tokenAmounts
        });

        vm.expectRevert(IAaveGhoCcipBridge.OnlySelf.selector);
        mainnetBridge.processMessage(message);

        vm.stopPrank();
    }
}

contract CcipReceiveTest is AaveGhoCcipBridgeForkTestBase {
    function test_revertsIf_invalidRouter() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        // build dummy message for test
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
            sender: abi.encode(address(0)),
            data: "",
            destTokenAmounts: tokenAmounts
        });

        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, admin));
        mainnetBridge.ccipReceive(message);

        vm.stopPrank();
    }

    function test_successful_receivedInvalidMessage() public {
        vm.startPrank(admin);
        vm.selectFork(mainnetFork);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        // build dummy message for test
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: ARBITRUM_CHAIN_SELECTOR,
            sender: abi.encode(address(0)),
            data: "",
            destTokenAmounts: tokenAmounts
        });
        vm.stopPrank();

        vm.startPrank(mainnetBridge.ROUTER());

        vm.expectEmit(address(mainnetBridge));
        emit IAaveGhoCcipBridge.FailedToFinalizeBridge(bytes32(0), hex"5ea23900");
        mainnetBridge.ccipReceive(message);

        vm.stopPrank();
    }
}

contract QuoteTransferTest is AaveGhoCcipBridgeForkTestBase {
    address public feeToken = address(0);

    function test_revertsIf_unsupportedChain() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.UnsupportedChain.selector);
        mainnetBridge.quoteBridge(BLAST_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);
    }

    function test_revertsIf_invalidTransferAmount() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);
        vm.expectRevert(IAaveGhoCcipBridge.InvalidZeroAmount.selector);
        mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, 0, 0, feeToken);
    }

    function test_revertsIf_rateLimitExceeded() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);
        uint128 limit = mainnetBridge.getRateLimit(ARBITRUM_CHAIN_SELECTOR);
        vm.expectRevert(abi.encodeWithSelector(IAaveGhoCcipBridge.RateLimitExceeded.selector, limit));
        mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, limit + 1, 0, feeToken);
    }

    function test_revertsIf_invalidFeeToken() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(facilitator);
        vm.expectRevert(abi.encodeWithSelector(NotAFeeToken.selector, address(1)));
        mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, address(1));
    }

    function test_successful() public {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);
        uint256 fee = mainnetBridge.quoteBridge(ARBITRUM_CHAIN_SELECTOR, AMOUNT_TO_SEND, 0, feeToken);

        assertGt(fee, 0);
    }
}

contract RescuableTest is AaveGhoCcipBridgeForkTestBase {
    uint256 amount = 100_000 ether;

    function test_revertsIf_callertNotRescueGuardian() public {
        vm.selectFork(mainnetFork);
        vm.expectRevert(IRescuable.OnlyRescueGuardian.selector);
        mainnetBridge.emergencyTokenTransfer(
            AaveV3EthereumAssets.GHO_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), amount
        );
    }

    function test_successful() public {
        vm.selectFork(mainnetFork);
        deal(AaveV3EthereumAssets.GHO_UNDERLYING, address(mainnetBridge), amount);

        assertEq(mainnetBridge.whoCanRescue(), admin);
        assertEq(mainnetBridge.maxRescue(AaveV3EthereumAssets.GHO_UNDERLYING), amount);

        uint256 balanceBefore = IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.prank(admin);
        mainnetBridge.emergencyTokenTransfer(
            AaveV3EthereumAssets.GHO_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), amount
        );

        assertEq(
            IERC20(AaveV3EthereumAssets.GHO_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
            balanceBefore + amount
        );
    }
}

contract GetInvalidMessage is AaveGhoCcipBridgeForkTestBase {
    address public feeToken = AaveV3EthereumAssets.GHO_UNDERLYING;

    function test_revertIf_messageNotFound() external {
        vm.selectFork(mainnetFork);
        vm.startPrank(admin);

        vm.expectRevert(IAaveGhoCcipBridge.MessageNotFound.selector);
        mainnetBridge.getInvalidMessage(bytes32(0));
        vm.stopPrank();
    }

    function test_success() external {
        Internal.EVM2EVMMessage memory message = _buildInvalidMessage();

        vm.selectFork(arbitrumFork);
        vm.startPrank(admin);

        Client.EVMTokenAmount[] memory tokenAmounts = arbitrumBridge.getInvalidMessage(message.messageId);
        assertEq(tokenAmounts.length, 1);
    }
}
