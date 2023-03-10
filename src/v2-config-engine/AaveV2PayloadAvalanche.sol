// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV2Avalanche} from 'aave-address-book/AaveV2Avalanche.sol';
import {ILendingPoolConfigurator} from 'aave-address-book/AaveV2.sol';
import './AaveV2RatePayloadBase.sol';

/**
 * @dev Base smart contract for an Aave v2 rates update on Avalanche.
 * @author BGD Labs
 */
// TODO: Add rates factory address after deploying
abstract contract AaveV2PayloadAvalanche is
  AaveV2RatePayloadBase(Rates(address(0)), ILendingPoolConfigurator(AaveV2Avalanche.POOL_CONFIGURATOR))
{
  function getPoolContext() public pure override returns (PoolContext memory) {
    return PoolContext({networkName: 'Avalanche', networkAbbreviation: 'Ava'});
  }
}
