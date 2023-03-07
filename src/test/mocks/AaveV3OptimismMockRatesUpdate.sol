// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../v3-config-engine/AaveV3PayloadOptimism.sol';

/**
 * @dev Smart contract for a mock rate strategy params update, for testing purposes
 * IMPORTANT Parameters are pseudo-random, DON'T USE THIS ANYHOW IN PRODUCTION
 * @author BGD Labs
 */
contract AaveV3OptimismMockRatesUpdate is AaveV3PayloadBase {
  constructor(IEngine customEngine) AaveV3PayloadBase(customEngine) {}

  function rateStrategiesUpdates()
    public
    pure
    override
    returns (IEngine.RateStrategyUpdate[] memory)
  {
    IEngine.RateStrategyUpdate[] memory ratesUpdate = new IEngine.RateStrategyUpdate[](1);

    ratesUpdate[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3OptimismAssets.USDT_UNDERLYING,
      params: Rates.RateStrategyParams({
        optimalUsageRatio: _bpsToRay(80_00),
        baseVariableBorrowRate: EngineFlags.KEEP_CURRENT,
        variableRateSlope1: EngineFlags.KEEP_CURRENT,
        variableRateSlope2: _bpsToRay(75_00),
        stableRateSlope1: EngineFlags.KEEP_CURRENT,
        stableRateSlope2: _bpsToRay(75_00),
        baseStableRateOffset: EngineFlags.KEEP_CURRENT,
        stableRateExcessOffset: EngineFlags.KEEP_CURRENT,
        optimalStableToTotalDebtRatio: EngineFlags.KEEP_CURRENT
      })
    });

    return ratesUpdate;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Optimism', networkAbbreviation: 'Opt'});
  }
}
