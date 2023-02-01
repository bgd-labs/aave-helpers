// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;
pragma abicoder v2;

import {Vm} from 'forge-std/Vm.sol';
import {Test} from 'forge-std/Test.sol';
import {AaveGovernanceV2, IAaveGovernanceV2, IExecutorWithTimelock} from 'aave-address-book/AaveGovernanceV2.sol';
import {IPoolAddressesProvider} from 'aave-address-book/AaveV3.sol';
import {AaveMisc} from 'aave-address-book/AaveMisc.sol';
import {ProxyHelpers} from './ProxyHelpers.sol';

library GovHelpers {
  struct SPropCreateParams {
    address executor;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    bool[] withDelegatecalls;
    bytes32 ipfsHash;
  }

  struct DelegateCallProposal {
    address target;
    string signature;
    bytes callData;
  }

  function createMainnetDelegateCall(address payloadAddress)
    internal
    returns (DelegateCallProposal memory)
  {
    return DelegateCallProposal({target: payloadAddress, signature: 'execute()', callData: ''});
  }

  function createOptimismDelegateCall(address payloadAddress)
    internal
    returns (DelegateCallProposal memory)
  {
    return
      DelegateCallProposal({
        target: AaveGovernanceV2.CROSSCHAIN_FORWARDER_OPTIMISM,
        signature: 'execute(address)',
        callData: abi.encode(payloadAddress)
      });
  }

  function createArbitrumDelegateCall(address payloadAddress)
    internal
    returns (DelegateCallProposal memory)
  {
    return
      DelegateCallProposal({
        target: AaveGovernanceV2.CROSSCHAIN_FORWARDER_ARBITRUM,
        signature: 'execute(address)',
        callData: abi.encode(payloadAddress)
      });
  }

  function createPolygonDelegateCall(address payloadAddress)
    internal
    returns (DelegateCallProposal memory)
  {
    return
      DelegateCallProposal({
        target: AaveGovernanceV2.CROSSCHAIN_FORWARDER_POLYGON,
        signature: 'execute(address)',
        callData: abi.encode(payloadAddress)
      });
  }

  function createDelegateCallProposal(DelegateCallProposal[] memory delegateCalls, bytes32 ipfsHash)
    internal
    returns (uint256)
  {
    address[] memory targets = new address[](delegateCalls.length);
    uint256[] memory values = new uint256[](delegateCalls.length);
    string[] memory signatures = new string[](delegateCalls.length);
    bytes[] memory calldatas = new bytes[](delegateCalls.length);
    bool[] memory withDelegatecalls = new bool[](delegateCalls.length);
    for (uint256 i = 0; i < delegateCalls.length; i++) {
      targets[i] = delegateCalls[i].target;
      signatures[i] = delegateCalls[i].signature;
      calldatas[i] = delegateCalls[i].callData;
      values[i] = 0;
      withDelegatecalls[i] = true;
    }

    return
      AaveGovernanceV2.GOV.create(
        IExecutorWithTimelock(AaveGovernanceV2.SHORT_EXECUTOR),
        targets,
        values,
        signatures,
        calldatas,
        withDelegatecalls,
        ipfsHash
      );
  }

  /**
   * Impersonate the ecosystem reserve and created the proposal.
   */
  function createProposalAsWhale(Vm vm, SPropCreateParams memory params)
    internal
    returns (uint256)
  {
    vm.deal(AaveMisc.ECOSYSTEM_RESERVE, 1 ether);
    vm.startPrank(AaveMisc.ECOSYSTEM_RESERVE);
    uint256 proposalId = AaveGovernanceV2.GOV.create(
      IExecutorWithTimelock(params.executor),
      params.targets,
      params.values,
      params.signatures,
      params.calldatas,
      params.withDelegatecalls,
      params.ipfsHash
    );
    vm.stopPrank();
    return proposalId;
  }

  function _getProposalSlot(uint256 proposalId) private pure returns (bytes32 slot) {
    uint256 proposalsMapSlot = 0x4;
    return bytes32(uint256(keccak256(abi.encode(proposalId, proposalsMapSlot))) + 11);
  }

  /**
   * Alter storage slots so the proposal passes
   */
  function passVoteAndExecute(Vm vm, uint256 proposalId) internal {
    uint256 power = 5000000 ether;
    vm.roll(block.number + 1);
    vm.store(address(AaveGovernanceV2.GOV), _getProposalSlot(proposalId), bytes32(power));
    uint256 endBlock = AaveGovernanceV2.GOV.getProposalById(proposalId).endBlock;
    vm.roll(endBlock + 1);
    AaveGovernanceV2.GOV.queue(proposalId);
    uint256 executionTime = AaveGovernanceV2.GOV.getProposalById(proposalId).executionTime;
    vm.warp(executionTime + 1);
    AaveGovernanceV2.GOV.execute(proposalId);
  }

  function getProposalById(uint256 proposalId)
    internal
    view
    returns (IAaveGovernanceV2.ProposalWithoutVotes memory)
  {
    return AaveGovernanceV2.GOV.getProposalById(proposalId);
  }
}

/**
 * @dev Mock contract which allows performing a delegatecall to `execute`
 * Intended to be used as replacement for L2 admins to mock governance/gnosis execution.
 */
contract MockExecutor {
  function execute(address payload) public {
    (bool success, ) = address(payload).delegatecall(abi.encodeWithSignature('execute()'));
    require(success, 'PROPOSAL_EXECUTION_FAILED');
  }
}

/**
 * @dev Inheriting from this contract in a forge test allows to
 * 1. Configure on the setUp() of the child contract an executor for governance proposals
 *    (or any address with permissions) just by doing for example a `_selectPayloadExecutor(AaveGovernanceV2.SHORT_EXECUTOR)`
 * 2. Afterwards, on a test you can just do `_executePayload(somePayloadAddress)`, and it will be executed via
 *    DELEGATECALL on the address previously selected on step 1).
 */
abstract contract TestWithExecutor is Test {
  MockExecutor internal _executor;

  function _selectPayloadExecutor(address executor) internal {
    MockExecutor mockExecutor = new MockExecutor();
    vm.etch(executor, address(mockExecutor).code);

    _executor = MockExecutor(executor);
  }

  function _executePayload(address payload) internal {
    _executor.execute(payload);
  }
}
