// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../v3-config-engine/AaveV3PayloadAvalanche.sol';

/**
 * @dev Smart contract for a mock collateral update, for testing purposes
 * IMPORTANT Parameters are pseudo-random, DON'T USE THIS ANYHOW IN PRODUCTION
 * @author BGD Labs
 */
contract AaveV3AvalancheCollateralUpdate is AaveV3PayloadBase {
  constructor(IEngine customEngine) AaveV3PayloadBase(customEngine) {}

  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralsUpdate = new IEngine.CollateralUpdate[](1);

    collateralsUpdate[0] = IEngine.CollateralUpdate({
      asset: AaveV3AvalancheAssets.AAVEe_UNDERLYING,
      ltv: 62_00,
      liqThreshold: 72_00,
      liqBonus: 6_00,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: EngineFlags.KEEP_CURRENT
    });

    return collateralsUpdate;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Arbitrum', networkAbbreviation: 'Arb'});
  }
}
