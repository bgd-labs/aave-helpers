// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Arbitrum} from 'aave-address-book/AaveV3Arbitrum.sol';
import './AaveV3Payload.sol';

/**
 * @dev Base smart contract for an Aave v3.0.1 (compatible with 3.0.0) listing on v3 Arbitrum.
 * @author BGD Labs
 */
abstract contract AaveV3PayloadArbitrum is AaveV3Payload(IEngine(AaveV3Arbitrum.CONFIG_ENGINE)) {
  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Arbitrum', networkAbbreviation: 'Arb'});
  }
}
