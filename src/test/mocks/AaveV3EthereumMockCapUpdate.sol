// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../v3-config-engine/AaveV3PayloadEthereum.sol';

/**
 * @dev Smart contract for a mock caps update, for testing purposes
 * IMPORTANT Parameters are pseudo-random, DON'T USE THIS ANYHOW IN PRODUCTION
 * @author BGD Labs
 */
contract AaveV3EthereumMockCapUpdate is AaveV3PayloadBase {
  constructor(IEngine customEngine) AaveV3PayloadBase(customEngine) {}

  function capsUpdates() public pure override returns (IEngine.CapsUpdate[] memory) {
    IEngine.CapsUpdate[] memory capsUpdate = new IEngine.CapsUpdate[](1);

    capsUpdate[0] = IEngine.CapsUpdate({
      asset: AaveV3EthereumAssets.AAVE_UNDERLYING,
      supplyCap: 1_000_000,
      borrowCap: EngineFlags.KEEP_CURRENT
    });

    return capsUpdate;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Ethereum', networkAbbreviation: 'Eth'});
  }
}
