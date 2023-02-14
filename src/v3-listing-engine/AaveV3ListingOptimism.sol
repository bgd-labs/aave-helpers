// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3ListingBase, IGenericV3ListingEngine} from './AaveV3ListingBase.sol';

/**
 * @dev Base smart contract for an Aave v3.0.1 (compatible with 3.0.0) listing on v3 Optimism.
 * @author BGD Labs
 */
abstract contract AaveV3ListingOptimism is AaveV3ListingBase {
  constructor(IGenericV3ListingEngine listingEngine) AaveV3ListingBase(listingEngine) {}

  function getPoolContext()
    public
    pure
    override
    returns (IGenericV3ListingEngine.PoolContext memory)
  {
    return
      IGenericV3ListingEngine.PoolContext({networkName: 'Optimism', networkAbbreviation: 'Opt'});
  }
}
