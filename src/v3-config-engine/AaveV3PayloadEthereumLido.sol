// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3EthereumLido} from 'aave-address-book/AaveV3EthereumLido.sol';
import 'aave-v3-origin/periphery/contracts/v3-config-engine/AaveV3Payload.sol';

/**
 * @dev Base smart contract for an Aave v3.0.1 (compatible with 3.0.0) listing on v3 Avalanche.
 * @author BGD Labs
 */
abstract contract AaveV3PayloadEthereumLido is AaveV3Payload(IEngine(AaveV3EthereumLido.CONFIG_ENGINE)) {
  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Ethereum', networkAbbreviation: 'Eth'});
  }
}
