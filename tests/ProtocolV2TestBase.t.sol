// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {ProtocolV2TestBase, ReserveConfig} from '../src/ProtocolV2TestBase.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets} from 'aave-address-book/AaveV2Ethereum.sol';
import {AaveV2EthereumAMM} from 'aave-address-book/AaveV2EthereumAMM.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {PayloadWithEmit} from './mocks/PayloadWithEmit.sol';
import {StorageWriter} from './mocks/StorageWriter.sol';

contract ProtocolV2TestBaseTest is ProtocolV2TestBase {
  function setUp() public {
    vm.createSelectFork('mainnet', 17627440);
  }

  // function testSnpashot() public {
  //   createConfigurationSnapshot('v2-report', AaveV2Ethereum.POOL);
  // }

  function testE2E() public {
    e2eTest(AaveV2Ethereum.POOL);
  }
}

contract ProtocolV2TestE2ETestAsset is ProtocolV2TestBase {
  function setUp() public {
    vm.createSelectFork('mainnet', 18572478);
  }

  function test_e2eTestAssetUSDT() public {
    ReserveConfig[] memory configs = _getReservesConfigs(AaveV2Ethereum.POOL);
    e2eTestAsset(
      AaveV2Ethereum.POOL,
      _findReserveConfig(configs, AaveV2EthereumAssets.DAI_UNDERLYING),
      _findReserveConfig(configs, AaveV2EthereumAssets.USDT_UNDERLYING)
    );
  }

  function test_defaultTest() public {
    defaultTest('AMMTEST', AaveV2EthereumAMM.POOL, address(new PayloadWithEmit()), false, false);
  }
}

contract ProtocolV2TestStorageValidation is ProtocolV2TestBase {
  function setUp() public {
    vm.createSelectFork('mainnet', 21858534);
  }

  function test_noExecutorStorageChange_passes() public {
    address executor = makeAddr('executor');
    vm.startStateDiffRecording();
    _validateNoExecutorStorageChange(executor);
  }

  function test_executorStorageChange_reverts() public {
    StorageWriter writer = new StorageWriter();
    vm.startStateDiffRecording();
    writer.writeStorage();
    vm.expectRevert();
    _validateNoExecutorStorageChange(address(writer));
  }
}
