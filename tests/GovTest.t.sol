// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {GovHelpers} from '../src/GovHelpers.sol';
import {MiscEthereum} from 'aave-address-book/MiscEthereum.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {PayloadWithEmit} from './mocks/PayloadWithEmit.sol';

contract GovernanceTest is Test {
  function setUp() public {
    vm.createSelectFork('mainnet', 16526807);
  }

  function testCreateProposal() public {
    GovHelpers.Payload[] memory payloads = new GovHelpers.Payload[](2);
    payloads[0] = GovHelpers.buildMainnet(address(1));
    payloads[1] = GovHelpers.buildPolygon(address(2));

    vm.startPrank(MiscEthereum.ECOSYSTEM_RESERVE);
    GovHelpers.createProposal(payloads, bytes32('ipfs'));
    vm.stopPrank();
  }

  function testCreateProposalDynamicIpfsHash() public {
    GovHelpers.Payload[] memory payloads = new GovHelpers.Payload[](2);
    payloads[0] = GovHelpers.buildMainnet(address(1));
    payloads[1] = GovHelpers.buildPolygon(address(2));

    vm.startPrank(MiscEthereum.ECOSYSTEM_RESERVE);
    GovHelpers.createProposal(payloads, GovHelpers.ipfsHashFile(vm, 'tests/mocks/proposal.md'));
    vm.stopPrank();
  }
}

contract GovernanceL2ExecutorTest is Test {
  event TestEvent();

  function setUp() public {
    vm.createSelectFork('polygon', 43322560);
  }

  function testCreateProposal() public {
    PayloadWithEmit payload = new PayloadWithEmit();
    vm.expectEmit(true, true, true, true);
    emit TestEvent();
    GovHelpers.executePayload(vm, address(payload), AaveGovernanceV2.POLYGON_BRIDGE_EXECUTOR);
  }
}

contract GovernanceMainnetExecutorTest is Test {
  event TestEvent();

  function setUp() public {
    vm.createSelectFork('mainnet', 17570714);
  }

  function testCreateProposalShort() public {
    PayloadWithEmit payload = new PayloadWithEmit();
    vm.expectEmit(true, true, true, true);
    emit TestEvent();
    GovHelpers.executePayload(vm, address(payload), AaveGovernanceV2.SHORT_EXECUTOR);
  }

  function testCreateProposalLong() public {
    PayloadWithEmit payload = new PayloadWithEmit();
    vm.expectEmit(true, true, true, true);
    emit TestEvent();
    GovHelpers.executePayload(vm, address(payload), AaveGovernanceV2.LONG_EXECUTOR);
  }
}

contract GovernanceIpfsTest is Test {
  function testIpfsHashCreation() public {
    bytes32 bs58Hash = GovHelpers.ipfsHashFile(vm, 'tests/mocks/proposal.md');
    assertEq(
      bs58Hash,
      0x12f2d9c91e4e23ae4009ab9ef5862ee0ae79498937b66252213221f04a5d5b32,
      'HASH_MUST_MATCH'
    );
  }
}
