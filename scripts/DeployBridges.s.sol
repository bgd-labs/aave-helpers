// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ArbitrumScript, EthereumScript, PolygonScript} from 'src/ScriptUtils.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {GovernanceV3Polygon} from 'aave-address-book/GovernanceV3Polygon.sol';
import {GovernanceV3Arbitrum} from 'aave-address-book/GovernanceV3Arbitrum.sol';

import {AavePolEthERC20Bridge} from 'src/bridges/polygon/AavePolEthERC20Bridge.sol';
import {AaveArbEthERC20Bridge} from 'src/bridges/arbitrum/AaveArbEthERC20Bridge.sol';

contract DeployEthereum is EthereumScript {
  function run() external broadcast {
    bytes32 salt = 'Aave Treasury Bridge';
    new AavePolEthERC20Bridge{salt: salt}(GovernanceV3Ethereum.EXECUTOR_LVL_1);
  }
}

contract DeployPolygon is PolygonScript {
  function run() external broadcast {
    bytes32 salt = 'Aave Treasury Bridge';
    new AavePolEthERC20Bridge{salt: salt}(GovernanceV3Polygon.EXECUTOR_LVL_1);
  }
}

contract DeployArbitrum is ArbitrumScript {
  function run() external broadcast {
    bytes32 salt = 'Aave Treasury Bridge';
    new AaveArbEthERC20Bridge{salt: salt}(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
  }
}
