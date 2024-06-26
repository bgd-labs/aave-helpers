// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Metis} from 'aave-address-book/AaveV3Metis.sol';
import 'aave-v3-origin/periphery/contracts/v3-config-engine/AaveV3Payload.sol';

/**
 * @dev Base smart contract for an Aave v3.0.2 (compatible with 3.0.0) listing on v3 Metis.
 * @author BGD Labs
 */
abstract contract AaveV3PayloadMetis is AaveV3Payload(IEngine(AaveV3Metis.CONFIG_ENGINE)) {
  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Metis', networkAbbreviation: 'Met'});
  }
}
