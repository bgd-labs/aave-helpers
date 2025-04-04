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
contract AaveCcipGhoBridgeTestBase is Test {
  uint64 public constant SOURCE_CHAIN_SELECTOR = 5009297550715157269;
  uint64 public constant DESTINATION_CHAIN_SELECTOR = 4949039107694359620;

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

contract SetDestinationBridgeTest is AaveCcipGhoBridgeTestBase {
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
    bridge.setDestinationBridge(DESTINATION_CHAIN_SELECTOR, address(destinationBridge));
    vm.stopPrank();
  }

  function test_success() external {
    vm.startPrank(owner);

    vm.expectEmit(address(bridge));
    emit IAaveCcipGhoBridge.DestinationUpdated(
      DESTINATION_CHAIN_SELECTOR,
      address(destinationBridge)
    );
    bridge.setDestinationBridge(DESTINATION_CHAIN_SELECTOR, address(destinationBridge));

    assertEq(
      bridge.bridges(DESTINATION_CHAIN_SELECTOR),
      address(destinationBridge),
      'Destination bridge not set correctly in the mapping'
    );
    vm.stopPrank();
  }
}

contract ProcessMessageTest is AaveCcipGhoBridgeTestBase {
  function test_reverts_OnlySelf() public {
    vm.startPrank(owner);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: DESTINATION_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(IAaveCcipGhoBridge.OnlySelf.selector);
    bridge.processMessage(message);

    vm.stopPrank();
  }
}

contract CcipReceiveTest is AaveCcipGhoBridgeTestBase {
  function test_reverts_InvalidRouter() public {
    vm.startPrank(owner);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: DESTINATION_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, owner));
    bridge.ccipReceive(message);

    vm.stopPrank();
  }

  function test_successWith_ReceivedInvalidMessage() public {
    vm.startPrank(bridge.ROUTER());

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: DESTINATION_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectEmit(address(bridge));
    emit IAaveCcipGhoBridge.ReceivedInvalidMessage(bytes32(0));
    bridge.ccipReceive(message);

    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(bridge.ROUTER());
    // fund to bridge
    deal(address(gho), address(bridge), amount);

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: address(gho), amount: amount});

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: DESTINATION_CHAIN_SELECTOR,
      sender: abi.encode(address(0)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.expectEmit(true, true, false, true, address(bridge));
    emit IAaveCcipGhoBridge.TransferFinished(bytes32(0), collector, amount);
    bridge.ccipReceive(message);

    vm.stopPrank();
  }
}

contract HandleInvalidMessageTest is AaveCcipGhoBridgeTestBase {
  address public feeToken = address(gho);

  function _buildInvalidMessage() internal returns (Client.Any2EVMMessage memory) {
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: address(gho), amount: amount});

    // build dummy message for test
    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(0),
      sourceChainSelector: DESTINATION_CHAIN_SELECTOR,
      sender: abi.encode(address(1)),
      data: '',
      destTokenAmounts: tokenAmounts
    });

    vm.startPrank(bridge.ROUTER());
    bridge.ccipReceive(message);
    vm.stopPrank();

    return message;
  }

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
    bridge.handleInvalidMessage(bytes32(0));
    vm.stopPrank();
  }

  function test_revertIf_MessageNotFound() external {
    vm.startPrank(owner);

    vm.expectRevert(IAaveCcipGhoBridge.MessageNotFound.selector);
    bridge.handleInvalidMessage(bytes32('1'));
    vm.stopPrank();
  }

  function test_success() external {
    // fund to bridge
    deal(address(gho), address(bridge), amount);
    Client.Any2EVMMessage memory message = _buildInvalidMessage();

    vm.startPrank(owner);

    uint256 balanceBefore = gho.balanceOf(collector);

    vm.expectEmit(true, false, false, false, address(bridge));
    emit IAaveCcipGhoBridge.HandledInvalidMessage(message.messageId);
    bridge.handleInvalidMessage(message.messageId);

    uint256 balanceAfter = gho.balanceOf(collector);

    assertEq(balanceAfter, balanceBefore + amount);

    vm.stopPrank();
  }
}

contract RescuableTest is AaveCcipGhoBridgeTestBase {
  function test_assert() external {
    deal(address(gho), address(bridge), amount);
    assertEq(bridge.whoCanRescue(), owner);
    assertEq(bridge.maxRescue(address(gho)), amount);
  }
}
