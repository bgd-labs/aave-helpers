// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {IAaveV3ConfigEngine as IEngine, IPoolConfigurator, IV3RateStrategyFactory, IPool} from '../IAaveV3ConfigEngine.sol';
import {PriceFeedEngine} from './PriceFeedEngine.sol';
import {CapsEngine} from './CapsEngine.sol';
import {BorrowEngine} from './BorrowEngine.sol';
import {CollateralEngine} from './CollateralEngine.sol';
import {EModeEngine} from './EModeEngine.sol';
import {ConfiguratorInputTypes} from 'aave-address-book/AaveV3.sol';
import {Address} from 'solidity-utils/contracts/oz-common/Address.sol';

library ListingEngine {
  using Address for address;

  function executeCustomAssetListing(
    IEngine.PoolContext calldata context,
    IEngine.EngineConstants calldata engineConstants,
    IEngine.EngineLibraries calldata engineLibraries,
    IEngine.ListingWithCustomImpl[] calldata listings
  ) external {
    require(listings.length != 0, 'AT_LEAST_ONE_ASSET_REQUIRED');

    IEngine.RepackedListings memory repacked = _repackListing(listings);

    engineLibraries.priceFeedEngine.functionDelegateCall(
      abi.encodeWithSelector(
        PriceFeedEngine.executePriceFeedsUpdate.selector,
        engineConstants,
        repacked.priceFeedsUpdates
      )
    );

    _initAssets(
      context,
      engineConstants.poolConfigurator,
      engineConstants.ratesStrategyFactory,
      engineConstants.collector,
      engineConstants.rewardsController,
      repacked.ids,
      repacked.basics,
      repacked.rates
    );

    engineLibraries.capsEngine.functionDelegateCall(
      abi.encodeWithSelector(
        CapsEngine.executeCapsUpdate.selector,
        engineConstants,
        repacked.capsUpdates
      )
    );

    engineLibraries.borrowEngine.functionDelegateCall(
      abi.encodeWithSelector(
        BorrowEngine.executeBorrowSide.selector,
        engineConstants,
        repacked.borrowsUpdates
      )
    );

    engineLibraries.collateralEngine.functionDelegateCall(
      abi.encodeWithSelector(
        CollateralEngine.executeCollateralSide.selector,
        engineConstants,
        repacked.collateralsUpdates
      )
    );

    // For an asset listing we only update the e-mode category id for the asset and do not make changes
    // to the e-mode category configuration
    engineLibraries.eModeEngine.functionDelegateCall(
      abi.encodeWithSelector(
        EModeEngine.executeAssetsEModeUpdate.selector,
        engineConstants,
        repacked.assetsEModeUpdates
      )
    );
  }

  function _repackListing(
    IEngine.ListingWithCustomImpl[] calldata listings
  ) internal pure returns (IEngine.RepackedListings memory) {
    address[] memory ids = new address[](listings.length);
    IEngine.BorrowUpdate[] memory borrowsUpdates = new IEngine.BorrowUpdate[](listings.length);
    IEngine.CollateralUpdate[] memory collateralsUpdates = new IEngine.CollateralUpdate[](
      listings.length
    );
    IEngine.PriceFeedUpdate[] memory priceFeedsUpdates = new IEngine.PriceFeedUpdate[](
      listings.length
    );
    IEngine.AssetEModeUpdate[] memory assetsEModeUpdates = new IEngine.AssetEModeUpdate[](
      listings.length
    );
    IEngine.CapsUpdate[] memory capsUpdates = new IEngine.CapsUpdate[](listings.length);

    IEngine.Basic[] memory basics = new IEngine.Basic[](listings.length);
    IV3RateStrategyFactory.RateStrategyParams[]
      memory rates = new IV3RateStrategyFactory.RateStrategyParams[](listings.length);

    for (uint256 i = 0; i < listings.length; i++) {
      require(listings[i].base.asset != address(0), 'INVALID_ASSET');
      ids[i] = listings[i].base.asset;
      basics[i] = IEngine.Basic({
        assetSymbol: listings[i].base.assetSymbol,
        implementations: listings[i].implementations
      });
      priceFeedsUpdates[i] = IEngine.PriceFeedUpdate({
        asset: listings[i].base.asset,
        priceFeed: listings[i].base.priceFeed
      });
      borrowsUpdates[i] = IEngine.BorrowUpdate({
        asset: listings[i].base.asset,
        enabledToBorrow: listings[i].base.enabledToBorrow,
        flashloanable: listings[i].base.flashloanable,
        stableRateModeEnabled: listings[i].base.stableRateModeEnabled,
        borrowableInIsolation: listings[i].base.borrowableInIsolation,
        withSiloedBorrowing: listings[i].base.withSiloedBorrowing,
        reserveFactor: listings[i].base.reserveFactor
      });
      collateralsUpdates[i] = IEngine.CollateralUpdate({
        asset: listings[i].base.asset,
        ltv: listings[i].base.ltv,
        liqThreshold: listings[i].base.liqThreshold,
        liqBonus: listings[i].base.liqBonus,
        debtCeiling: listings[i].base.debtCeiling,
        liqProtocolFee: listings[i].base.liqProtocolFee
      });
      capsUpdates[i] = IEngine.CapsUpdate({
        asset: listings[i].base.asset,
        supplyCap: listings[i].base.supplyCap,
        borrowCap: listings[i].base.borrowCap
      });
      rates[i] = listings[i].base.rateStrategyParams;
      assetsEModeUpdates[i] = IEngine.AssetEModeUpdate({
        asset: listings[i].base.asset,
        eModeCategory: listings[i].base.eModeCategory
      });
    }

    return
      IEngine.RepackedListings(
        ids,
        basics,
        borrowsUpdates,
        collateralsUpdates,
        priceFeedsUpdates,
        assetsEModeUpdates,
        capsUpdates,
        rates
      );
  }

  /// @dev mandatory configurations for any asset getting listed, including oracle config and basic init
  function _initAssets(
    IEngine.PoolContext calldata context,
    IPoolConfigurator poolConfigurator,
    IV3RateStrategyFactory rateStrategiesFactory,
    address collector,
    address rewardsController,
    address[] memory ids,
    IEngine.Basic[] memory basics,
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
