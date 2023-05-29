// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {EngineFlags} from '../EngineFlags.sol';
import {AaveV3ConfigEngine as Engine} from '../AaveV3ConfigEngine.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {IAaveV3ConfigEngine as IEngine, IPoolConfigurator, IV3RateStrategyFactory, IAaveOracle, IPool} from '../IAaveV3ConfigEngine.sol';
import {PriceFeedEngine} from './PriceFeedEngine.sol';
import {CapsEngine} from './CapsEngine.sol';
import {BorrowEngine} from './BorrowEngine.sol';
import {CollateralEngine} from './CollateralEngine.sol';
import {ConfiguratorInputTypes} from 'aave-address-book/AaveV3.sol';

library ListingEngine {
  function executeCustomAssetListing(
    IEngine.PoolContext memory context,
    IPoolConfigurator poolConfigurator,
    IV3RateStrategyFactory rateStrategiesFactory,
    IPool pool,
    IAaveOracle oracle,
    address collector,
    address rewardsController,
    IEngine.ListingWithCustomImpl[] memory listings
  ) external {
    require(listings.length != 0, 'AT_LEAST_ONE_ASSET_REQUIRED');

    Engine.AssetsConfig memory configs = _repackListing(listings);

    PriceFeedEngine.setPriceFeeds(oracle, configs.ids, configs.basics);

    _initAssets(
      context,
      poolConfigurator,
      rateStrategiesFactory,
      collector,
      rewardsController,
      configs.ids, 
      configs.basics, 
      configs.rates
    );

    CapsEngine.configureCaps(poolConfigurator, configs.ids, configs.caps);

    BorrowEngine.configBorrowSide(poolConfigurator, pool, configs.ids, configs.borrows);

    CollateralEngine.configCollateralSide(poolConfigurator, pool, configs.ids, configs.collaterals);
  }

  function _repackListing(IEngine.ListingWithCustomImpl[] memory listings)
    internal
    pure
    returns (Engine.AssetsConfig memory)
  {
    address[] memory ids = new address[](listings.length);
    Engine.Basic[] memory basics = new Engine.Basic[](listings.length);
    Engine.Borrow[] memory borrows = new Engine.Borrow[](listings.length);
    Engine.Collateral[] memory collaterals = new Engine.Collateral[](listings.length);
    Engine.Caps[] memory caps = new Engine.Caps[](listings.length);
    IV3RateStrategyFactory.RateStrategyParams[]
      memory rates = new IV3RateStrategyFactory.RateStrategyParams[](listings.length);

    for (uint256 i = 0; i < listings.length; i++) {
      require(listings[i].base.asset != address(0), 'INVALID_ASSET');
      ids[i] = listings[i].base.asset;
      basics[i] = Engine.Basic({
        assetSymbol: listings[i].base.assetSymbol,
        priceFeed: listings[i].base.priceFeed,
        rateStrategyParams: listings[i].base.rateStrategyParams,
        implementations: listings[i].implementations
      });
      borrows[i] = Engine.Borrow({
        enabledToBorrow: listings[i].base.enabledToBorrow,
        flashloanable: listings[i].base.flashloanable,
        stableRateModeEnabled: listings[i].base.stableRateModeEnabled,
        borrowableInIsolation: listings[i].base.borrowableInIsolation,
        withSiloedBorrowing: listings[i].base.withSiloedBorrowing,
        reserveFactor: listings[i].base.reserveFactor
      });
      collaterals[i] = Engine.Collateral({
        ltv: listings[i].base.ltv,
        liqThreshold: listings[i].base.liqThreshold,
        liqBonus: listings[i].base.liqBonus,
        debtCeiling: listings[i].base.debtCeiling,
        liqProtocolFee: listings[i].base.liqProtocolFee,
        eModeCategory: listings[i].base.eModeCategory
      });
      caps[i] = Engine.Caps({
        supplyCap: listings[i].base.supplyCap,
        borrowCap: listings[i].base.borrowCap
      });
      rates[i] = listings[i].base.rateStrategyParams;
    }

    return
      Engine.AssetsConfig({
        ids: ids,
        basics: basics,
        borrows: borrows,
        collaterals: collaterals,
        caps: caps,
        rates: rates,
        eModeCategories: new Engine.EModeCategories[](0)
      });
  }

  /// @dev mandatory configurations for any asset getting listed, including oracle config and basic init
  function _initAssets(
    IEngine.PoolContext memory context,
    IPoolConfigurator poolConfigurator,
    IV3RateStrategyFactory rateStrategiesFactory,
    address collector,
    address rewardsController,
    address[] memory ids,
    Engine.Basic[] memory basics,
    IV3RateStrategyFactory.RateStrategyParams[] memory rates
  ) internal {
    ConfiguratorInputTypes.InitReserveInput[]
      memory initReserveInputs = new ConfiguratorInputTypes.InitReserveInput[](ids.length);
    address[] memory strategies = rateStrategiesFactory.createStrategies(rates);

    for (uint256 i = 0; i < ids.length; i++) {
      uint8 decimals = IERC20Metadata(ids[i]).decimals();
      require(decimals > 0, 'INVALID_ASSET_DECIMALS');

      initReserveInputs[i] = ConfiguratorInputTypes.InitReserveInput({
        aTokenImpl: basics[i].implementations.aToken,
        stableDebtTokenImpl: basics[i].implementations.sToken,
        variableDebtTokenImpl: basics[i].implementations.vToken,
        underlyingAssetDecimals: decimals,
        interestRateStrategyAddress: strategies[i],
        underlyingAsset: ids[i],
        treasury: collector,
        incentivesController: rewardsController,
        aTokenName: string.concat('Aave ', context.networkName, ' ', basics[i].assetSymbol),
        aTokenSymbol: string.concat('a', context.networkAbbreviation, basics[i].assetSymbol),
        variableDebtTokenName: string.concat(
          'Aave ',
          context.networkName,
          ' Variable Debt ',
          basics[i].assetSymbol
        ),
        variableDebtTokenSymbol: string.concat(
          'variableDebt',
          context.networkAbbreviation,
          basics[i].assetSymbol
        ),
        stableDebtTokenName: string.concat(
          'Aave ',
          context.networkName,
          ' Stable Debt ',
          basics[i].assetSymbol
        ),
        stableDebtTokenSymbol: string.concat(
          'stableDebt',
          context.networkAbbreviation,
          basics[i].assetSymbol
        ),
        params: bytes('')
      });
    }
    poolConfigurator.initReserves(initReserveInputs);
  }
}