// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import 'forge-std/Test.sol';
import {IAaveOracle, ILendingPool, ILendingPoolAddressesProvider, ILendingPoolConfigurator, IAaveProtocolDataProvider, DataTypes, TokenData, ILendingRateOracle, IDefaultInterestRateStrategy} from 'aave-address-book/AaveV2.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {AaveV2EthereumAMM} from 'aave-address-book/AaveV2EthereumAMM.sol';
import {AaveV2EthereumAssets} from 'aave-address-book/AaveV2Ethereum.sol';
import {IInitializableAdminUpgradeabilityProxy} from './interfaces/IInitializableAdminUpgradeabilityProxy.sol';
import {ExtendedAggregatorV2V3Interface} from './interfaces/ExtendedAggregatorV2V3Interface.sol';
import {CommonTestBase, ReserveTokens} from './CommonTestBase.sol';
import {ProxyHelpers} from './ProxyHelpers.sol';
import {ChainIds} from './ChainIds.sol';
import {SnapshotHelpersV2} from './SnapshotHelpersV2.sol';

struct ReserveConfig {
  string symbol;
  address underlying;
  address aToken;
  address stableDebtToken;
  address variableDebtToken;
  uint256 decimals;
  uint256 ltv;
  uint256 liquidationThreshold;
  uint256 liquidationBonus;
  uint256 reserveFactor;
  bool usageAsCollateralEnabled;
  bool borrowingEnabled;
  address interestRateStrategy;
  bool stableBorrowRateEnabled;
  bool isActive;
  bool isFrozen;
}

struct LocalVars {
  TokenData[] reserves;
  ReserveConfig[] configs;
}

struct InterestStrategyValues {
  address addressesProvider;
  uint256 optimalUsageRatio;
  uint256 stableRateSlope1;
  uint256 stableRateSlope2;
  uint256 baseVariableBorrowRate;
  uint256 variableRateSlope1;
  uint256 variableRateSlope2;
}

contract ProtocolV2TestBase is CommonTestBase {
  using SafeERC20 for IERC20;

  SnapshotHelpersV2 public snapshotHelper;

  function setUp() virtual public {
    snapshotHelper = new SnapshotHelpersV2();
  }

  /**
   * @dev runs the default test suite that should run on any proposal touching the aave protocol which includes:
   * - diffing the config
   * - running an e2e testsuite over all assets
   */
  function defaultTest(
    string memory reportName,
    ILendingPool pool,
    address payload
  ) public returns (ReserveConfig[] memory, ReserveConfig[] memory) {
    return defaultTest(reportName, pool, payload, true);
  }

  function defaultTest(
    string memory reportName,
    ILendingPool pool,
    address payload,
    bool runE2E
  ) public returns (ReserveConfig[] memory, ReserveConfig[] memory) {
    string memory beforeString = string(abi.encodePacked(reportName, '_before'));
    ReserveConfig[] memory configBefore = createConfigurationSnapshot(beforeString, pool);

    executePayload(vm, payload);

    string memory afterString = string(abi.encodePacked(reportName, '_after'));
    ReserveConfig[] memory configAfter = createConfigurationSnapshot(afterString, pool);

    diffReports(beforeString, afterString);

    if (runE2E) e2eTest(pool);
    return (configBefore, configAfter);
  }

  /**
   * @dev Generates a markdown compatible snapshot of the whole pool configuration into `/reports`.
   * @param reportName filename suffix for the generated reports.
   * @param pool the pool to be snapshotted
   * @return ReserveConfig[] list of configs
   */
  function createConfigurationSnapshot(
    string memory reportName,
    ILendingPool pool
  ) public returns (ReserveConfig[] memory) {
    return snapshotHelper.createConfigurationSnapshot(reportName, pool);
  }

  /**
   * @dev Makes a e2e test including withdrawals/borrows and supplies to various reserves.
   * @param pool the pool that should be tested
   */
  function e2eTest(ILendingPool pool) public {
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    ReserveConfig memory collateralConfig = _getGoodCollateral(configs);
    uint256 snapshot = vm.snapshot();
    for (uint256 i; i < configs.length; i++) {
      if (_includeInE2e(configs[i])) {
        e2eTestAsset(pool, collateralConfig, configs[i]);
        vm.revertTo(snapshot);
      }
    }
  }

  function e2eTestAsset(
    ILendingPool pool,
    ReserveConfig memory collateralConfig,
    ReserveConfig memory testAssetConfig
  ) public {
    console.log(
      'E2E: Collateral %s, TestAsset %s',
      collateralConfig.symbol,
      testAssetConfig.symbol
    );
    address collateralSupplier = vm.addr(3);
    address testAssetSupplier = vm.addr(4);
    require(collateralConfig.usageAsCollateralEnabled, 'COLLATERAL_CONFIG_MUST_BE_COLLATERAL');
    uint256 testAssetAmount = _getTokenAmountByEthValue(pool, testAssetConfig, 1);
    _deposit(
      collateralConfig,
      pool,
      collateralSupplier,
      _getTokenAmountByEthValue(pool, collateralConfig, 100)
    );
    _deposit(testAssetConfig, pool, testAssetSupplier, testAssetAmount);
    uint256 snapshot = vm.snapshot();
    // test withdrawal
    _withdraw(testAssetConfig, pool, testAssetSupplier, testAssetAmount / 2);
    _withdraw(testAssetConfig, pool, testAssetSupplier, type(uint256).max);
    vm.revertTo(snapshot);
    // test variable borrowing
    if (testAssetConfig.borrowingEnabled) {
      _e2eTestBorrowRepay(pool, collateralSupplier, testAssetConfig, testAssetAmount, false);
      vm.revertTo(snapshot);
      // test stable borrowing
      if (testAssetConfig.stableBorrowRateEnabled) {
        _e2eTestBorrowRepay(pool, collateralSupplier, testAssetConfig, testAssetAmount, true);
        vm.revertTo(snapshot);
      }
    }
  }

  /**
   * Reserves that are frozen or not active should not be included in e2e test suite
   */
  function _includeInE2e(ReserveConfig memory config) internal pure returns (bool) {
    return !config.isFrozen && config.isActive;
  }

  function _getTokenAmountByEthValue(
    ILendingPool pool,
    ReserveConfig memory config,
    uint256 dollarValue
  ) internal view returns (uint256) {
    ILendingPoolAddressesProvider addressesProvider = ILendingPoolAddressesProvider(
      pool.getAddressesProvider()
    );
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    uint256 latestAnswer = oracle.getAssetPrice(config.underlying);
    return (dollarValue * 10 ** (18 + config.decimals)) / latestAnswer;
  }

  function _e2eTestBorrowRepay(
    ILendingPool pool,
    address borrower,
    ReserveConfig memory testAssetConfig,
    uint256 amount,
    bool stable
  ) internal {
    uint256 snapshot = vm.snapshot();
    this._borrow(testAssetConfig, pool, borrower, amount, stable);
    // switching back and forth between rate modes should work
    if (testAssetConfig.stableBorrowRateEnabled) {
      vm.startPrank(borrower);
      pool.swapBorrowRateMode(testAssetConfig.underlying, stable ? 1 : 2);
      pool.swapBorrowRateMode(testAssetConfig.underlying, stable ? 2 : 1);
    } else {
      vm.expectRevert();
      pool.swapBorrowRateMode(testAssetConfig.underlying, stable ? 1 : 2);
    }
    _repay(testAssetConfig, pool, borrower, amount, stable);
    vm.revertTo(snapshot);
  }

  /**
   * @dev returns a "good" collateral in the list that cannot be borrowed in stable mode
   */
  function _getGoodCollateral(
    ReserveConfig[] memory configs
  ) private pure returns (ReserveConfig memory config) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (
        _includeInE2e(configs[i]) &&
        configs[i].usageAsCollateralEnabled &&
        !configs[i].stableBorrowRateEnabled
      ) return configs[i];
    }
    revert('ERROR: No usable collateral found');
  }

  function _deposit(
    ReserveConfig memory config,
    ILendingPool pool,
    address user,
    uint256 amount
  ) internal {
    vm.startPrank(user);
    uint256 aTokenBefore = IERC20(config.aToken).balanceOf(user);
    deal2(config.underlying, user, amount);
    IERC20(config.underlying).forceApprove(address(pool), amount);
    pool.deposit(config.underlying, amount, user, 0);
    console.log('SUPPLY: %s, Amount: %s', config.symbol, amount);
    uint256 aTokenAfter = IERC20(config.aToken).balanceOf(user);
    if (
      block.chainid == ChainIds.MAINNET &&
      config.underlying == AaveV2EthereumAssets.stETH_UNDERLYING
    ) {
      assertApproxEqAbs(aTokenAfter, aTokenBefore + amount, 2, '_deposit(): STETH_DUST_GT_2');
    } else {
      assertApproxEqAbs(aTokenAfter, aTokenBefore + amount, 1, '_deposit(): STETH_DUST_GT_1');
    }
    vm.stopPrank();
  }

  function _withdraw(
    ReserveConfig memory config,
    ILendingPool pool,
    address user,
    uint256 amount
  ) internal returns (uint256) {
    vm.startPrank(user);
    uint256 aTokenBefore = IERC20(config.aToken).balanceOf(user);
    uint256 amountOut = pool.withdraw(config.underlying, amount, user);
    console.log('WITHDRAW: %s, Amount: %s', config.symbol, amountOut);
    uint256 aTokenAfter = IERC20(config.aToken).balanceOf(user);
    if (aTokenBefore < amount) {
      if (
        block.chainid == ChainIds.MAINNET &&
        config.underlying == AaveV2EthereumAssets.stETH_UNDERLYING
      ) {
        assertApproxEqAbs(aTokenAfter, 0, 2, '_withdraw(): STETH_DUST_GT_2');
      } else {
        require(aTokenAfter == 0, '_withdraw(): DUST_AFTER_WITHDRAW_ALL');
      }
    } else {
      if (
        block.chainid == ChainIds.MAINNET &&
        config.underlying == AaveV2EthereumAssets.stETH_UNDERLYING
      ) {
        assertApproxEqAbs(aTokenAfter, aTokenBefore - amount, 2, '_withdraw(): STETH_DUST_GT_2');
      } else {
        assertApproxEqAbs(aTokenAfter, aTokenBefore - amount, 1, '_withdraw(): DUST_GT_1');
      }
    }
    vm.stopPrank();
    return amountOut;
  }

  function _borrow(
    ReserveConfig memory config,
    ILendingPool pool,
    address user,
    uint256 amount,
    bool stable
  ) external {
    vm.startPrank(user);
    address debtToken = stable ? config.stableDebtToken : config.variableDebtToken;
    uint256 debtBefore = IERC20(debtToken).balanceOf(user);
    console.log('BORROW: %s, Amount %s, Stable: %s', config.symbol, amount, stable);
    pool.borrow(config.underlying, amount, stable ? 1 : 2, 0, user);
    uint256 debtAfter = IERC20(debtToken).balanceOf(user);
    if (
      block.chainid == ChainIds.MAINNET &&
      config.underlying == AaveV2EthereumAssets.stETH_UNDERLYING
    ) {
      assertApproxEqAbs(debtAfter, debtBefore + amount, 2, '_borrow(): DUST_GT_2');
    } else {
      assertApproxEqAbs(debtAfter, debtBefore + amount, 1, '_borrow(): DUST_GT_1');
    }
    vm.stopPrank();
  }

  function _repay(
    ReserveConfig memory config,
    ILendingPool pool,
    address user,
    uint256 amount,
    bool stable
  ) internal {
    vm.startPrank(user);
    address debtToken = stable ? config.stableDebtToken : config.variableDebtToken;
    uint256 debtBefore = IERC20(debtToken).balanceOf(user);
    deal2(config.underlying, user, amount);
    IERC20(config.underlying).forceApprove(address(pool), amount);
    console.log('REPAY: %s, Amount: %s', config.symbol, amount);
    pool.repay(config.underlying, amount, stable ? 1 : 2, user);
    uint256 debtAfter = IERC20(debtToken).balanceOf(user);
    if (amount >= debtBefore) {
      assertEq(debtAfter, 0, '_repay() : ERROR MUST_BE_ZERO');
    } else {
      assertApproxEqAbs(debtAfter, debtBefore - amount, 1, '_repay() : ERROR MAX_ONE_OFF');
    }
    vm.stopPrank();
  }

  function _writeStrategyConfigs(string memory path, ReserveConfig[] memory configs) internal {
    return snapshotHelper.writeStrategyConfigs(path, configs);
  }

  function _writePoolConfiguration(string memory path, ILendingPool pool) internal {
    return snapshotHelper.writePoolConfiguration(path, pool);
  }

  function _writeReserveConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    ILendingPool pool,
    ILendingRateOracle rateOracle
  ) internal {
    return snapshotHelper.writeReserveConfigs(path, configs, pool, rateOracle);
  }

  function _getReservesConfigs(ILendingPool pool) internal view returns (ReserveConfig[] memory) {
    return snapshotHelper.getReservesConfigs(pool);
  }

  function _getStructReserveTokens(
    IAaveProtocolDataProvider pdp,
    address underlyingAddress
  ) internal view returns (ReserveTokens memory) {
    return snapshotHelper.getStructReserveTokens(pdp, underlyingAddress);
  }

  function _getStructReserveConfig(
    ILendingPool pool,
    IAaveProtocolDataProvider pdp,
    TokenData memory reserve
  ) internal view virtual returns (ReserveConfig memory) {
    return snapshotHelper.getStructReserveConfig(pool, pdp, reserve);
  }

  // TODO This should probably be simplified with assembly, too much boilerplate
  function _clone(ReserveConfig memory config) internal pure returns (ReserveConfig memory) {
    return
      ReserveConfig({
        symbol: config.symbol,
        underlying: config.underlying,
        aToken: config.aToken,
        stableDebtToken: config.stableDebtToken,
        variableDebtToken: config.variableDebtToken,
        decimals: config.decimals,
        ltv: config.ltv,
        liquidationThreshold: config.liquidationThreshold,
        liquidationBonus: config.liquidationBonus,
        reserveFactor: config.reserveFactor,
        usageAsCollateralEnabled: config.usageAsCollateralEnabled,
        borrowingEnabled: config.borrowingEnabled,
        interestRateStrategy: config.interestRateStrategy,
        stableBorrowRateEnabled: config.stableBorrowRateEnabled,
        isActive: config.isActive,
        isFrozen: config.isFrozen
      });
  }

  function _findReserveConfig(
    ReserveConfig[] memory configs,
    address underlying
  ) internal pure returns (ReserveConfig memory) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (configs[i].underlying == underlying) {
        // Important to clone the struct, to avoid unexpected side effect if modifying the returned config
        return _clone(configs[i]);
      }
    }
    revert('RESERVE_CONFIG_NOT_FOUND');
  }

  function _findReserveConfigBySymbol(
    ReserveConfig[] memory configs,
    string memory symbolOfUnderlying
  ) internal pure returns (ReserveConfig memory) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (
        keccak256(abi.encodePacked(configs[i].symbol)) ==
        keccak256(abi.encodePacked(symbolOfUnderlying))
      ) {
        return _clone(configs[i]);
      }
    }
    revert('RESERVE_CONFIG_NOT_FOUND');
  }

  function _logReserveConfig(ReserveConfig memory config) internal view {
    console.log('Symbol ', config.symbol);
    console.log('Underlying address ', config.underlying);
    console.log('AToken address ', config.aToken);
    console.log('Stable debt token address ', config.stableDebtToken);
    console.log('Variable debt token address ', config.variableDebtToken);
    console.log('Decimals ', config.decimals);
    console.log('LTV ', config.ltv);
    console.log('Liquidation Threshold ', config.liquidationThreshold);
    console.log('Liquidation Bonus ', config.liquidationBonus);
    console.log('Reserve Factor ', config.reserveFactor);
    console.log('Usage as collateral enabled ', (config.usageAsCollateralEnabled) ? 'Yes' : 'No');
    console.log('Borrowing enabled ', (config.borrowingEnabled) ? 'Yes' : 'No');
    console.log('Stable borrow rate enabled ', (config.stableBorrowRateEnabled) ? 'Yes' : 'No');
    console.log('Interest rate strategy ', config.interestRateStrategy);
    console.log('Is active ', (config.isActive) ? 'Yes' : 'No');
    console.log('Is frozen ', (config.isFrozen) ? 'Yes' : 'No');
    console.log('-----');
    console.log('-----');
  }

  function _validateReserveConfig(
    ReserveConfig memory expectedConfig,
    ReserveConfig[] memory allConfigs
  ) internal pure {
    ReserveConfig memory config = _findReserveConfig(allConfigs, expectedConfig.underlying);
    require(
      keccak256(bytes(config.symbol)) == keccak256(bytes(expectedConfig.symbol)),
      '_validateConfigsInAave() : INVALID_SYMBOL'
    );
    require(
      config.underlying == expectedConfig.underlying,
      '_validateConfigsInAave() : INVALID_UNDERLYING'
    );
    require(config.decimals == expectedConfig.decimals, '_validateConfigsInAave: INVALID_DECIMALS');
    require(config.ltv == expectedConfig.ltv, '_validateConfigsInAave: INVALID_LTV');
    require(
      config.liquidationThreshold == expectedConfig.liquidationThreshold,
      '_validateConfigsInAave: INVALID_LIQ_THRESHOLD'
    );
    require(
      config.liquidationBonus == expectedConfig.liquidationBonus,
      '_validateConfigsInAave: INVALID_LIQ_BONUS'
    );
    require(
      config.reserveFactor == expectedConfig.reserveFactor,
      '_validateConfigsInAave: INVALID_RESERVE_FACTOR'
    );

    require(
      config.usageAsCollateralEnabled == expectedConfig.usageAsCollateralEnabled,
      '_validateConfigsInAave: INVALID_USAGE_AS_COLLATERAL'
    );
    require(
      config.borrowingEnabled == expectedConfig.borrowingEnabled,
      '_validateConfigsInAave: INVALID_BORROWING_ENABLED'
    );
    require(
      config.stableBorrowRateEnabled == expectedConfig.stableBorrowRateEnabled,
      '_validateConfigsInAave: INVALID_STABLE_BORROW_ENABLED'
    );
    require(
      config.isActive == expectedConfig.isActive,
      '_validateConfigsInAave: INVALID_IS_ACTIVE'
    );
    require(
      config.isFrozen == expectedConfig.isFrozen,
      '_validateConfigsInAave: INVALID_IS_FROZEN'
    );
    require(
      config.interestRateStrategy == expectedConfig.interestRateStrategy,
      '_validateConfigsInAave: INVALID_INTEREST_RATE_STRATEGY'
    );
  }

  function _validateInterestRateStrategy(
    address interestRateStrategyAddress,
    address expectedStrategy,
    InterestStrategyValues memory expectedStrategyValues
  ) internal view {
    IDefaultInterestRateStrategy strategy = IDefaultInterestRateStrategy(
      interestRateStrategyAddress
    );

    require(
      address(strategy) == expectedStrategy,
      '_validateInterestRateStrategy() : INVALID_STRATEGY_ADDRESS'
    );

    require(
      strategy.OPTIMAL_UTILIZATION_RATE() == expectedStrategyValues.optimalUsageRatio,
      '_validateInterestRateStrategy() : INVALID_OPTIMAL_RATIO'
    );
    require(
      address(strategy.addressesProvider()) == expectedStrategyValues.addressesProvider,
      '_validateInterestRateStrategy() : INVALID_ADDRESSES_PROVIDER'
    );
    require(
      strategy.baseVariableBorrowRate() == expectedStrategyValues.baseVariableBorrowRate,
      '_validateInterestRateStrategy() : INVALID_BASE_VARIABLE_BORROW'
    );
    require(
      strategy.stableRateSlope1() == expectedStrategyValues.stableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_1'
    );
    require(
      strategy.stableRateSlope2() == expectedStrategyValues.stableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_2'
    );
    require(
      strategy.variableRateSlope1() == expectedStrategyValues.variableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_1'
    );
    require(
      strategy.variableRateSlope2() == expectedStrategyValues.variableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_2'
    );
  }

  function _noReservesConfigsChangesApartNewListings(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter
  ) internal pure {
    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
    }
  }

  function _noReservesConfigsChangesApartFrom(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter,
    address assetChangedUnderlying
  ) internal pure {
    require(allConfigsBefore.length == allConfigsAfter.length, 'A_UNEXPECTED_NEW_LISTING_HAPPENED');

    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      if (assetChangedUnderlying != allConfigsBefore[i].underlying) {
        _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
      }
    }
  }

  /// @dev Version in batch, useful when multiple asset changes are expected
  function _noReservesConfigsChangesApartFrom(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter,
    address[] memory assetChangedUnderlying
  ) internal pure {
    require(allConfigsBefore.length == allConfigsAfter.length, 'A_UNEXPECTED_NEW_LISTING_HAPPENED');

    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      bool isAssetExpectedToChange;
      for (uint256 j = 0; j < assetChangedUnderlying.length; j++) {
        if (assetChangedUnderlying[j] == allConfigsBefore[i].underlying) {
          isAssetExpectedToChange = true;
          break;
        }
      }
      if (!isAssetExpectedToChange) {
        _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
      }
    }
  }

  function _requireNoChangeInConfigs(
    ReserveConfig memory config1,
    ReserveConfig memory config2
  ) internal pure {
    require(
      keccak256(abi.encodePacked(config1.symbol)) == keccak256(abi.encodePacked(config2.symbol)),
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_SYMBOL_CHANGED'
    );
    require(
      config1.underlying == config2.underlying,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_UNDERLYING_CHANGED'
    );
    require(
      config1.aToken == config2.aToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_A_TOKEN_CHANGED'
    );
    require(
      config1.stableDebtToken == config2.stableDebtToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_STABLE_DEBT_TOKEN_CHANGED'
    );
    require(
      config1.variableDebtToken == config2.variableDebtToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_VARIABLE_DEBT_TOKEN_CHANGED'
    );
    require(
      config1.decimals == config2.decimals,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_DECIMALS_CHANGED'
    );
    require(
      config1.ltv == config2.ltv,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LTV_CHANGED'
    );
    require(
      config1.liquidationThreshold == config2.liquidationThreshold,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LIQ_THRESHOLD_CHANGED'
    );
    require(
      config1.liquidationBonus == config2.liquidationBonus,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LIQ_BONUS_CHANGED'
    );
    require(
      config1.reserveFactor == config2.reserveFactor,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_RESERVE_FACTOR_CHANGED'
    );
    require(
      config1.usageAsCollateralEnabled == config2.usageAsCollateralEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_USAGE_AS_COLLATERAL_ENABLED_CHANGED'
    );
    require(
      config1.borrowingEnabled == config2.borrowingEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_BORROWING_ENABLED_CHANGED'
    );
    require(
      config1.interestRateStrategy == config2.interestRateStrategy,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_INTEREST_RATE_STRATEGY_CHANGED'
    );
    require(
      config1.stableBorrowRateEnabled == config2.stableBorrowRateEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_STABLE_BORROWING_CHANGED'
    );
    require(
      config1.isActive == config2.isActive,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_ACTIVE_CHANGED'
    );
    require(
      config1.isFrozen == config2.isFrozen,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_FROZEN_CHANGED'
    );
  }

  function _validateCountOfListings(
    uint256 count,
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter
  ) internal pure {
    require(
      allConfigsBefore.length == allConfigsAfter.length - count,
      '_validateCountOfListings() : INVALID_COUNT_OF_LISTINGS'
    );
  }

  function _validateReserveTokensImpls(
    ILendingPoolAddressesProvider addressProvider,
    ReserveConfig memory config,
    ReserveTokens memory expectedImpls
  ) internal {
    address poolConfigurator = addressProvider.getLendingPoolConfigurator();
    vm.startPrank(poolConfigurator);
    require(
      IInitializableAdminUpgradeabilityProxy(config.aToken).implementation() ==
        expectedImpls.aToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    require(
      IInitializableAdminUpgradeabilityProxy(config.variableDebtToken).implementation() ==
        expectedImpls.variableDebtToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    require(
      IInitializableAdminUpgradeabilityProxy(config.stableDebtToken).implementation() ==
        expectedImpls.stableDebtToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    vm.stopPrank();
  }

  function _validateAssetSourceOnOracle(
    ILendingPoolAddressesProvider addressProvider,
    address asset,
    address expectedSource
  ) internal view {
    IAaveOracle oracle = IAaveOracle(addressProvider.getPriceOracle());

    require(
      oracle.getSourceOfAsset(asset) == expectedSource,
      '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
    );
  }
}
