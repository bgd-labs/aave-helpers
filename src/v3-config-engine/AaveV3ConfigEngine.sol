// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ConfiguratorInputTypes, DataTypes} from 'aave-address-book/AaveV3.sol';
import {ReserveConfiguration} from 'aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
import {EngineFlags} from './EngineFlags.sol';
import './IAaveV3ConfigEngine.sol';

/**
 * @dev Helper smart contract abstracting the complexity of changing configurations on Aave v3, simplifying
 * listing flow and parameters updates.
 * - It is planned to be used via delegatecall, by any contract having appropriate permissions to
 * do a listing, or any other granular config
 * Assumptions:
 * - Only one a/v/s token implementation for all assets
 * - Only one RewardsController for all assets
 * - Only one Collector for all assets
 * @author BGD Labs
 */
contract AaveV3ConfigEngine is IAaveV3ConfigEngine {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  struct AssetsConfig {
    address[] ids;
    Basic[] basics;
    Borrow[] borrows;
    Collateral[] collaterals;
    Caps[] caps;
    IV3RateStrategyFactory.RateStrategyParams[] rates;
  }

  struct Basic {
    string assetSymbol;
    address priceFeed;
    IV3RateStrategyFactory.RateStrategyParams rateStrategyParams;
  }

  struct Borrow {
    bool enabledToBorrow; // Main config flag, if false, some of the other fields will not be considered
    bool flashloanable;
    bool stableRateModeEnabled;
    bool borrowableInIsolation;
    bool withSiloedBorrowing;
    uint256 reserveFactor; // With 2 digits precision, `10_00` for 10%. Should be positive and < 100_00
  }

  struct Collateral {
    uint256 ltv; // Only considered if liqThreshold > 0. With 2 digits precision, `10_00` for 10%. Should be lower than liquidationThreshold
    uint256 liqThreshold; // If `0`, the asset will not be enabled as collateral. Same format as ltv, and should be higher
    uint256 liqBonus; // Only considered if liqThreshold > 0. Same format as ltv
    uint256 debtCeiling; // Only considered if liqThreshold > 0. In USD and with 2 digits for decimals, e.g. 10_000_00 for 10k
    uint256 liqProtocolFee; // Only considered if liqThreshold > 0. Same format as ltv
    uint256 eModeCategory;
  }

  struct Caps {
    uint256 supplyCap; // Always configured. In "big units" of the asset, and no decimals. 100 for 100 ETH supply cap
    uint256 borrowCap; // Always configured, no matter if enabled for borrowing or not. Same format as supply cap
  }

  IPool public immutable POOL;
  IPoolConfigurator public immutable POOL_CONFIGURATOR;
  IAaveOracle public immutable ORACLE;
  address public immutable ATOKEN_IMPL;
  address public immutable VTOKEN_IMPL;
  address public immutable STOKEN_IMPL;
  address public immutable REWARDS_CONTROLLER;
  address public immutable COLLECTOR;
  IV3RateStrategyFactory public immutable RATE_STRATEGIES_FACTORY;

  constructor(
    IPool pool,
    IPoolConfigurator configurator,
    IAaveOracle oracle,
    address aTokenImpl,
    address vTokenImpl,
    address sTokenImpl,
    address rewardsController,
    address collector,
    IV3RateStrategyFactory rateStrategiesFactory
  ) {
    require(address(pool) != address(0), 'ONLY_NONZERO_POOL');
    require(address(configurator) != address(0), 'ONLY_NONZERO_CONFIGURATOR');
    require(address(oracle) != address(0), 'ONLY_NONZERO_ORACLE');
    require(aTokenImpl != address(0), 'ONLY_NONZERO_ATOKEN');
    require(vTokenImpl != address(0), 'ONLY_NONZERO_VTOKEN');
    require(sTokenImpl != address(0), 'ONLY_NONZERO_STOKEN');
    require(rewardsController != address(0), 'ONLY_NONZERO_REWARDS_CONTROLLER');
    require(collector != address(0), 'ONLY_NONZERO_COLLECTOR');

    POOL = pool;
    POOL_CONFIGURATOR = configurator;
    ORACLE = oracle;
    ATOKEN_IMPL = aTokenImpl;
    VTOKEN_IMPL = vTokenImpl;
    STOKEN_IMPL = sTokenImpl;
    REWARDS_CONTROLLER = rewardsController;
    COLLECTOR = collector;
    RATE_STRATEGIES_FACTORY = rateStrategiesFactory;
  }

  /// @inheritdoc IAaveV3ConfigEngine
  function listAssets(PoolContext memory context, Listing[] memory listings) public {
    require(listings.length != 0, 'AT_LEAST_ONE_ASSET_REQUIRED');

    AssetsConfig memory configs = _repackListing(listings);

    _setPriceFeeds(configs.ids, configs.basics);

    _initAssets(context, configs.ids, configs.basics, configs.rates);

    _configureCaps(configs.ids, configs.caps);

    _configBorrowSide(configs.ids, configs.borrows);

    _configCollateralSide(configs.ids, configs.collaterals);
  }

  /// @inheritdoc IAaveV3ConfigEngine
  function updateCaps(CapsUpdate[] memory updates) public {
    require(updates.length != 0, 'AT_LEAST_ONE_UPDATE_REQUIRED');

    AssetsConfig memory configs = _repackCapsUpdate(updates);

    _configureCaps(configs.ids, configs.caps);
  }

  /// @inheritdoc IAaveV3ConfigEngine
  function updateCollateralSide(CollateralUpdate[] memory updates) public {
    require(updates.length != 0, 'AT_LEAST_ONE_UPDATE_REQUIRED');

    AssetsConfig memory configs = _repackCollateralUpdate(updates);

    _configCollateralSide(configs.ids, configs.collaterals);
  }

  /// @inheritdoc IAaveV3ConfigEngine
  function updateRateStrategies(RateStrategyUpdate[] memory updates) public {
    require(updates.length != 0, 'AT_LEAST_ONE_UPDATE_REQUIRED');

    AssetsConfig memory configs = _repackRatesUpdate(updates);

    _configRateStrategies(configs.ids, configs.rates);
  }

  function _setPriceFeeds(address[] memory ids, Basic[] memory basics) internal {
    address[] memory assets = new address[](ids.length);
    address[] memory sources = new address[](ids.length);

    for (uint256 i = 0; i < ids.length; i++) {
      require(basics[i].priceFeed != address(0), 'PRICE_FEED_ALWAYS_REQUIRED');
      require(
        IChainlinkAggregator(basics[i].priceFeed).latestAnswer() > 0,
        'FEED_SHOULD_RETURN_POSITIVE_PRICE'
      );
      assets[i] = ids[i];
      sources[i] = basics[i].priceFeed;
    }

    ORACLE.setAssetSources(assets, sources);
  }

  /// @dev mandatory configurations for any asset getting listed, including oracle config and basic init
  function _initAssets(
    PoolContext memory context,
    address[] memory ids,
    Basic[] memory basics,
    IV3RateStrategyFactory.RateStrategyParams[] memory rates
  ) internal {
    ConfiguratorInputTypes.InitReserveInput[]
      memory initReserveInputs = new ConfiguratorInputTypes.InitReserveInput[](ids.length);
    address[] memory strategies = RATE_STRATEGIES_FACTORY.createStrategies(rates);

    for (uint256 i = 0; i < ids.length; i++) {
      uint8 decimals = IERC20Metadata(ids[i]).decimals();
      require(decimals > 0, 'INVALID_ASSET_DECIMALS');

      initReserveInputs[i] = ConfiguratorInputTypes.InitReserveInput({
        aTokenImpl: ATOKEN_IMPL,
        stableDebtTokenImpl: STOKEN_IMPL,
        variableDebtTokenImpl: VTOKEN_IMPL,
        underlyingAssetDecimals: decimals,
        interestRateStrategyAddress: strategies[i],
        underlyingAsset: ids[i],
        treasury: COLLECTOR,
        incentivesController: REWARDS_CONTROLLER,
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
    POOL_CONFIGURATOR.initReserves(initReserveInputs);
  }

  function _configureCaps(address[] memory ids, Caps[] memory caps) internal {
    for (uint256 i = 0; i < ids.length; i++) {
      if (caps[i].supplyCap != EngineFlags.KEEP_CURRENT) {
        POOL_CONFIGURATOR.setSupplyCap(ids[i], caps[i].supplyCap);
      }

      if (caps[i].borrowCap != EngineFlags.KEEP_CURRENT) {
        POOL_CONFIGURATOR.setBorrowCap(ids[i], caps[i].borrowCap);
      }
    }
  }

  function _configBorrowSide(address[] memory ids, Borrow[] memory borrows) internal {
    for (uint256 i = 0; i < ids.length; i++) {
      if (borrows[i].enabledToBorrow) {
        POOL_CONFIGURATOR.setReserveBorrowing(ids[i], true);

        // If enabled to borrow, the reserve factor should always be configured and > 0
        require(
          borrows[i].reserveFactor > 0 && borrows[i].reserveFactor < 100_00,
          'INVALID_RESERVE_FACTOR'
        );
        POOL_CONFIGURATOR.setReserveFactor(ids[i], borrows[i].reserveFactor);

        if (borrows[i].stableRateModeEnabled) {
          POOL_CONFIGURATOR.setReserveStableRateBorrowing(ids[i], true);
        }

        if (borrows[i].borrowableInIsolation) {
          POOL_CONFIGURATOR.setBorrowableInIsolation(ids[i], true);
        }

        if (borrows[i].withSiloedBorrowing) {
          POOL_CONFIGURATOR.setSiloedBorrowing(ids[i], true);
        }
      }

      if (borrows[i].flashloanable) {
        POOL_CONFIGURATOR.setReserveFlashLoaning(ids[i], true);
      }
    }
  }

  function _configRateStrategies(
    address[] memory ids,
    IV3RateStrategyFactory.RateStrategyParams[] memory strategiesParams
  ) internal {
    for (uint256 i = 0; i < strategiesParams.length; i++) {
      if (
        strategiesParams[i].variableRateSlope1 == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].variableRateSlope2 == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].optimalUsageRatio == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].baseVariableBorrowRate == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].stableRateSlope1 == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].stableRateSlope2 == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].baseStableRateOffset == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].stableRateExcessOffset == EngineFlags.KEEP_CURRENT ||
        strategiesParams[i].optimalStableToTotalDebtRatio == EngineFlags.KEEP_CURRENT
      ) {
        IV3RateStrategyFactory.RateStrategyParams
          memory currentStrategyData = RATE_STRATEGIES_FACTORY.getCurrentRateData(ids[i]);

        if (strategiesParams[i].variableRateSlope1 == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].variableRateSlope1 = currentStrategyData.variableRateSlope1;
        }

        if (strategiesParams[i].variableRateSlope2 == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].variableRateSlope2 = currentStrategyData.variableRateSlope2;
        }

        if (strategiesParams[i].optimalUsageRatio == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].optimalUsageRatio = currentStrategyData.optimalUsageRatio;
        }

        if (strategiesParams[i].baseVariableBorrowRate == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].baseVariableBorrowRate = currentStrategyData.baseVariableBorrowRate;
        }

        if (strategiesParams[i].stableRateSlope1 == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].stableRateSlope1 = currentStrategyData.stableRateSlope1;
        }

        if (strategiesParams[i].stableRateSlope2 == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].stableRateSlope2 = currentStrategyData.stableRateSlope2;
        }

        if (strategiesParams[i].baseStableRateOffset == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].baseStableRateOffset = currentStrategyData.baseStableRateOffset;
        }

        if (strategiesParams[i].stableRateExcessOffset == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].stableRateExcessOffset = currentStrategyData.stableRateExcessOffset;
        }

        if (strategiesParams[i].optimalStableToTotalDebtRatio == EngineFlags.KEEP_CURRENT) {
          strategiesParams[i].optimalStableToTotalDebtRatio = currentStrategyData
            .optimalStableToTotalDebtRatio;
        }
      }
    }

    address[] memory strategies = RATE_STRATEGIES_FACTORY.createStrategies(strategiesParams);

    for (uint256 i = 0; i < strategies.length; i++) {
      POOL_CONFIGURATOR.setReserveInterestRateStrategyAddress(ids[i], strategies[i]);
    }
  }

  function _configCollateralSide(address[] memory ids, Collateral[] memory collaterals) internal {
    for (uint256 i = 0; i < ids.length; i++) {
      if (collaterals[i].liqThreshold != 0) {
        if (
          collaterals[i].ltv == EngineFlags.KEEP_CURRENT ||
          collaterals[i].liqThreshold == EngineFlags.KEEP_CURRENT ||
          collaterals[i].liqBonus == EngineFlags.KEEP_CURRENT
        ) {
          DataTypes.ReserveConfigurationMap memory configuration = POOL.getConfiguration(ids[i]);
          (
            uint256 currentLtv,
            uint256 currentLiqThreshold,
            uint256 currentLiqBonus,
            ,
            ,

          ) = configuration.getParams();

          if (collaterals[i].ltv == EngineFlags.KEEP_CURRENT) {
            collaterals[i].ltv = currentLtv;
          }

          if (collaterals[i].liqThreshold == EngineFlags.KEEP_CURRENT) {
            collaterals[i].liqThreshold = currentLiqThreshold;
          }

          if (collaterals[i].liqBonus == EngineFlags.KEEP_CURRENT) {
            collaterals[i].liqBonus = currentLiqBonus;
          }
        }

        require(
          collaterals[i].liqThreshold + collaterals[i].liqBonus < 100_00,
          'INVALID_LIQ_PARAMS_ABOVE_100'
        );
        require(collaterals[i].liqProtocolFee < 100_00, 'INVALID_LIQ_PROTOCOL_FEE');

        POOL_CONFIGURATOR.configureReserveAsCollateral(
          ids[i],
          collaterals[i].ltv,
          collaterals[i].liqThreshold,
          // For reference, this is to simplify the interaction with the Aave protocol,
          // as there the definition is as e.g. 105% (5% bonus for liquidators)
          100_00 + collaterals[i].liqBonus
        );

        if (collaterals[i].liqProtocolFee != EngineFlags.KEEP_CURRENT) {
          POOL_CONFIGURATOR.setLiquidationProtocolFee(ids[i], collaterals[i].liqProtocolFee);
        }

        if (collaterals[i].debtCeiling != EngineFlags.KEEP_CURRENT) {
          POOL_CONFIGURATOR.setDebtCeiling(ids[i], collaterals[i].debtCeiling);
        }
      }

      if (collaterals[i].eModeCategory != EngineFlags.KEEP_CURRENT) {
        POOL_CONFIGURATOR.setAssetEModeCategory(ids[i], safeToUint8(collaterals[i].eModeCategory));
      }
    }
  }

  function _repackListing(Listing[] memory listings) internal pure returns (AssetsConfig memory) {
    address[] memory ids = new address[](listings.length);
    Basic[] memory basics = new Basic[](listings.length);
    Borrow[] memory borrows = new Borrow[](listings.length);
    Collateral[] memory collaterals = new Collateral[](listings.length);
    Caps[] memory caps = new Caps[](listings.length);
    IV3RateStrategyFactory.RateStrategyParams[]
      memory rates = new IV3RateStrategyFactory.RateStrategyParams[](listings.length);

    for (uint256 i = 0; i < listings.length; i++) {
      require(listings[i].asset != address(0), 'INVALID_ASSET');
      ids[i] = listings[i].asset;
      basics[i] = Basic({
        assetSymbol: listings[i].assetSymbol,
        priceFeed: listings[i].priceFeed,
        rateStrategyParams: listings[i].rateStrategyParams
      });
      borrows[i] = Borrow({
        enabledToBorrow: listings[i].enabledToBorrow,
        flashloanable: listings[i].flashloanable,
        stableRateModeEnabled: listings[i].stableRateModeEnabled,
        borrowableInIsolation: listings[i].borrowableInIsolation,
        withSiloedBorrowing: listings[i].withSiloedBorrowing,
        reserveFactor: listings[i].reserveFactor
      });
      collaterals[i] = Collateral({
        ltv: listings[i].ltv,
        liqThreshold: listings[i].liqThreshold,
        liqBonus: listings[i].liqBonus,
        debtCeiling: listings[i].debtCeiling,
        liqProtocolFee: listings[i].liqProtocolFee,
        eModeCategory: listings[i].eModeCategory
      });
      caps[i] = Caps({supplyCap: listings[i].supplyCap, borrowCap: listings[i].borrowCap});
      rates[i] = listings[i].rateStrategyParams;
    }

    return
      AssetsConfig({
        ids: ids,
        basics: basics,
        borrows: borrows,
        collaterals: collaterals,
        caps: caps,
        rates: rates
      });
  }

  function _repackCapsUpdate(CapsUpdate[] memory updates)
    internal
    pure
    returns (AssetsConfig memory)
  {
    address[] memory ids = new address[](updates.length);
    Caps[] memory caps = new Caps[](updates.length);

    for (uint256 i = 0; i < updates.length; i++) {
      ids[i] = updates[i].asset;
      caps[i] = Caps({supplyCap: updates[i].supplyCap, borrowCap: updates[i].borrowCap});
    }

    return
      AssetsConfig({
        ids: ids,
        caps: caps,
        basics: new Basic[](0),
        borrows: new Borrow[](0),
        collaterals: new Collateral[](0),
        rates: new IV3RateStrategyFactory.RateStrategyParams[](0)
      });
  }

  function _repackRatesUpdate(RateStrategyUpdate[] memory updates)
    internal
    pure
    returns (AssetsConfig memory)
  {
    address[] memory ids = new address[](updates.length);
    IV3RateStrategyFactory.RateStrategyParams[]
      memory rates = new IV3RateStrategyFactory.RateStrategyParams[](updates.length);

    for (uint256 i = 0; i < updates.length; i++) {
      ids[i] = updates[i].asset;
      rates[i] = updates[i].params;
    }

    return
      AssetsConfig({
        ids: ids,
        rates: rates,
        basics: new Basic[](0),
        borrows: new Borrow[](0),
        caps: new Caps[](0),
        collaterals: new Collateral[](0)
      });
  }

  function _repackCollateralUpdate(CollateralUpdate[] memory updates)
    internal
    pure
    returns (AssetsConfig memory)
  {
    address[] memory ids = new address[](updates.length);
    Collateral[] memory collaterals = new Collateral[](updates.length);

    for (uint256 i = 0; i < updates.length; i++) {
      ids[i] = updates[i].asset;
      collaterals[i] = Collateral({
        ltv: updates[i].ltv,
        liqThreshold: updates[i].liqThreshold,
        liqBonus: updates[i].liqBonus,
        debtCeiling: updates[i].debtCeiling,
        liqProtocolFee: updates[i].liqProtocolFee,
        eModeCategory: updates[i].eModeCategory
      });
    }

    return
      AssetsConfig({
        ids: ids,
        caps: new Caps[](0),
        basics: new Basic[](0),
        borrows: new Borrow[](0),
        collaterals: collaterals,
        rates: new IV3RateStrategyFactory.RateStrategyParams[](0)
      });
  }

  function safeToUint8(uint256 value) internal pure returns (uint8) {
    require(value <= type(uint8).max, 'Value doesnt fit in 8 bits');
    return uint8(value);
  }
}
