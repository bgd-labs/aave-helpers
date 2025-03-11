// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';
import {Strings} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {MockCCIPRouter, Client, IRouterClient} from './mocks/MockRouter.sol';
import {Internal} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol';
import {AaveCcipGhoBridge, IAaveCcipGhoBridge, CCIPReceiver} from 'src/bridges/chainlink-ccip/AaveCcipGhoBridge.sol';

/// @dev forge test --match-path=tests/bridges/chainlink-ccip/AaveCcipGhoBridgeUnitTest.t.sol -vvv
contract AaveCcipGhoBridgeTest is Test {
  event TransferIssued(
    bytes32 indexed messageId,
    uint64 indexed destinationChainSelector,
    address indexed from,
    uint256 totalAmount
  );
  event TransferFinished(bytes32 indexed messageId, address indexed to, uint256 amount);
  event DestinationUpdated(uint64 indexed chainSelector, address indexed bridge);
  event CCIPSendRequested(Internal.EVM2EVMMessage message);
  event ReceivedInvalidMessage(bytes32 indexed messageId);
  event HandledInvalidMessage(bytes32 indexed messageId);

  uint64 public constant sourceChainSelector = 5009297550715157269;
  uint64 public constant destinationChainSelector = 4949039107694359620;

  uint256 public constant mockFee = 0.01 ether;
  uint256 public constant amount = 1_000 ether;
  uint256 public constant gasLimit = 0; // use default gasLimit

  IRouterClient public ccipRouter;
  IERC20 public gho;
  address public collector;
  address public owner;
  address public alice;
  address public destinationBridge;

  AaveCcipGhoBridge bridge;

  function setUp() public {
    collector = makeAddr('collector');
    owner = makeAddr('owner');
    alice = makeAddr('alice');
    destinationBridge = makeAddr('destBridge');

    MockCCIPRouter mockRouter = new MockCCIPRouter();
    ccipRouter = IRouterClient(address(mockRouter));
    mockRouter.setFee(mockFee);

    ERC20Mock mockGho = new ERC20Mock();
    gho = IERC20(address(mockGho));

    bridge = new AaveCcipGhoBridge(address(mockRouter), address(mockGho), collector, owner);

    vm.startPrank(alice);
    gho.approve(address(bridge), type(uint256).max);
    vm.stopPrank();
  }

  function _buildCCIPMessage(
    uint256 amount,
    uint256 gasLimit,
    address feeToken
  ) internal view returns (Client.EVM2AnyMessage memory message) {
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: address(gho), amount: amount});

    message = Client.EVM2AnyMessage({
      receiver: abi.encode(destinationBridge),
      data: '',
      tokenAmounts: tokenAmounts,
      extraArgs: gasLimit == 0
        ? bytes('')
        : Client._argsToBytes(
          Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: false})
        ),
      feeToken: feeToken
    });
  }
}

contract BridgeToken is AaveCcipGhoBridgeTest {
  function test_revertsIf_UnsupportedChain() external {
    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.UnsupportedChain.selector);
    bridge.bridge(destinationChainSelector, amount, gasLimit, address(gho));
  }

  function test_revertsIf_NotBridger() external {
    vm.prank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));

    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(bridge.BRIDGER_ROLE()), 32)
      )
    );
    bridge.bridge(destinationChainSelector, amount, gasLimit, address(gho));
  }

  function test_revertsIf_InvalidTransferAmount() external {
    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidTransferAmount.selector);
    bridge.bridge(destinationChainSelector, 0, 0, address(gho));
  }

  function test_success() external {
    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    uint256 fee = bridge.quoteBridge(destinationChainSelector, amount, gasLimit, address(gho));
    deal(address(gho), alice, amount + fee);
    deal(alice, 100);

    vm.startPrank(alice);

    Client.EVM2AnyMessage memory message = _buildCCIPMessage(amount, gasLimit, address(gho));

    // Expect call to CCIP send function
    vm.expectCall(
      address(ccipRouter),
      abi.encodeWithSelector(ccipRouter.ccipSend.selector, destinationChainSelector, message)
    );
    vm.expectEmit(false, true, true, true, address(bridge));
    emit TransferIssued(bytes32(0), destinationChainSelector, alice, amount);
    bridge.bridge{value: 100}(destinationChainSelector, amount, gasLimit, address(gho));
    vm.stopPrank();
  }

  function testFuzz_success(uint256 amount) external {
    vm.assume(amount > 0 && amount < 1e32);

    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    uint256 fee = bridge.quoteBridge(destinationChainSelector, amount, gasLimit, address(gho));
    deal(address(gho), alice, amount + fee);
    deal(alice, 100);

    vm.startPrank(alice);

    Client.EVM2AnyMessage memory message = _buildCCIPMessage(amount, gasLimit, address(gho));

    // Expect call to CCIP send function
    vm.expectCall(
      address(ccipRouter),
      abi.encodeWithSelector(ccipRouter.ccipSend.selector, destinationChainSelector, message)
    );
    vm.expectEmit(false, true, true, true, address(bridge));
    emit TransferIssued(bytes32(0), destinationChainSelector, alice, amount);
    bridge.bridge{value: 100}(destinationChainSelector, amount, gasLimit, address(gho));
  }

  function testFuzz_success_nativeFee(uint256 amount) external {
    vm.assume(amount > 0 && amount < 1e32);

    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);

    vm.stopPrank();

    uint256 fee = bridge.quoteBridge(destinationChainSelector, amount, gasLimit, address(0));
    deal(address(gho), alice, amount + fee);
    deal(alice, fee);

    vm.startPrank(alice);

    Client.EVM2AnyMessage memory message = _buildCCIPMessage(amount, gasLimit, address(0));

    // Expect call to CCIP send function
    vm.expectCall(
      address(ccipRouter),
      abi.encodeWithSelector(ccipRouter.ccipSend.selector, destinationChainSelector, message)
    );
    vm.expectEmit(false, true, true, true, address(bridge));
    emit TransferIssued(bytes32(0), destinationChainSelector, alice, amount);
    bridge.bridge{value: fee}(destinationChainSelector, amount, gasLimit, address(0));
  }
}

contract SetDestinationBridgeTest is AaveCcipGhoBridgeTest {
  function test_revertIf_NotOwner() external {
    vm.startPrank(alice);

    vm.expectRevert(
      abi.encodePacked(
        'AccessControl: account ',
        Strings.toHexString(uint160(alice), 20),
        ' is missing role ',
        Strings.toHexString(uint256(bridge.DEFAULT_ADMIN_ROLE()), 32)
      )
    );
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    vm.stopPrank();
  }

  function test_success() external {
    vm.startPrank(owner);

    vm.expectEmit(address(bridge));
    emit DestinationUpdated(destinationChainSelector, address(destinationBridge));
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));

    assertEq(
      bridge.bridges(destinationChainSelector),
      address(destinationBridge),
      'Destination bridge not set correctly in the mapping'
    );
    vm.stopPrank();
  }
}

contract ProcessMessageTest is AaveCcipGhoBridgeTest {
  function test_reverts_OnlySelf() public {
    vm.startPrank(owner);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: destinationChainSelector,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(IAaveCcipGhoBridge.OnlySelf.selector);
    bridge.processMessage(message);

    vm.stopPrank();
  }
}

contract CcipReceiveTest is AaveCcipGhoBridgeTest {
  function test_reverts_InvalidRouter() public {
    vm.startPrank(owner);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: destinationChainSelector,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, owner));
    bridge.ccipReceive(message);

    vm.stopPrank();
  }

  function test_successWith_ReceivedInvalidMessage() public {
    vm.startPrank(owner);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: destinationChainSelector,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });
    vm.stopPrank();

    vm.startPrank(bridge.ROUTER());

    vm.expectEmit(address(bridge));
    emit ReceivedInvalidMessage(bytes32(0));
    bridge.ccipReceive(message);

    vm.stopPrank();
  }
}

contract QuoteTransferTest is AaveCcipGhoBridgeTest {
  function test_revertsIf_UnsupportedChain() external {
    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.UnsupportedChain.selector);
    bridge.quoteBridge(destinationChainSelector, amount, gasLimit, address(gho));
  }

  function test_revertsIf_InvalidTransferAmount() external {
    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(IAaveCcipGhoBridge.InvalidTransferAmount.selector);
    bridge.quoteBridge(destinationChainSelector, 0, 0, address(gho));
  }

  function test_success() external {
    vm.startPrank(owner);
    bridge.setDestinationBridge(destinationChainSelector, address(destinationBridge));
    bridge.grantRole(bridge.BRIDGER_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(alice);
    uint256 fee = bridge.quoteBridge(destinationChainSelector, amount, gasLimit, address(gho));

    assertGt(fee, 0);
  }
}

contract RescuableTest is AaveCcipGhoBridgeTest {
  function test_assert() external {
    assertEq(bridge.whoCanRescue(), owner);
    assertEq(bridge.maxRescue(address(0)), type(uint256).max);
  }
}
