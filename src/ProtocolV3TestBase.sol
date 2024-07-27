// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import 'forge-std/Test.sol';
import {IAaveOracle, IPool, IPoolAddressesProvider, IPoolDataProvider, IReserveInterestRateStrategy, DataTypes, IPoolConfigurator} from 'aave-address-book/AaveV3.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {ReserveConfiguration} from 'aave-v3-origin/core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {DiffUtils} from 'aave-v3-origin/../tests/utils/DiffUtils.sol';
import {ProtocolV3TestBase as RawProtocolV3TestBase, ReserveConfig, ReserveTokens} from 'aave-v3-origin/../tests/utils/ProtocolV3TestBase.sol';
import {IInitializableAdminUpgradeabilityProxy} from './interfaces/IInitializableAdminUpgradeabilityProxy.sol';
import {ExtendedAggregatorV2V3Interface} from './interfaces/ExtendedAggregatorV2V3Interface.sol';
import {ProxyHelpers} from './ProxyHelpers.sol';
import {CommonTestBase} from './CommonTestBase.sol';
import {SnapshotHelpersV3} from './SnapshotHelpersV3.sol';
import {ILegacyDefaultInterestRateStrategy} from './dependencies/ILegacyDefaultInterestRateStrategy.sol';

struct LocalVars {
  IPoolDataProvider.TokenData[] reserves;
  ReserveConfig[] configs;
}

struct InterestStrategyValues {
  address addressesProvider;
  uint256 optimalUsageRatio;
  uint256 optimalStableToTotalDebtRatio;
  uint256 baseStableBorrowRate;
  uint256 stableRateSlope1;
  uint256 stableRateSlope2;
  uint256 baseVariableBorrowRate;
  uint256 variableRateSlope1;
  uint256 variableRateSlope2;
}

/**
 * only applicable to harmony at this point
 */
contract ProtocolV3TestBase is RawProtocolV3TestBase, CommonTestBase {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using SafeERC20 for IERC20;

  SnapshotHelpersV3 public snapshotHelper;

  function setUp() virtual public {
    snapshotHelper = new SnapshotHelpersV3();
  }

  /**
   * @dev runs the default test suite that should run on any proposal touching the aave protocol which includes:
   * - diffing the config
   * - checking if the changes are plausible (no conflicting config changes etc)
   * - running an e2e testsuite over all assets
   */
  function defaultTest(
    string memory reportName,
    IPool pool,
    address payload
  ) public returns (ReserveConfig[] memory, ReserveConfig[] memory) {
    return defaultTest(reportName, pool, payload, true);
  }

  function defaultTest(
    string memory reportName,
    IPool pool,
    address payload,
    bool runE2E
  ) public returns (ReserveConfig[] memory, ReserveConfig[] memory) {
    string memory beforeString = string(abi.encodePacked(reportName, '_before'));
    ReserveConfig[] memory configBefore = createConfigurationSnapshot(beforeString, pool);

    uint256 startGas = gasleft();

    executePayload(vm, payload);

    uint256 gasUsed = startGas - gasleft();
    assertLt(gasUsed, (block.gaslimit * 95) / 100, 'BLOCK_GAS_LIMIT_EXCEEDED'); // 5% is kept as a buffer

    string memory afterString = string(abi.encodePacked(reportName, '_after'));
    ReserveConfig[] memory configAfter = createConfigurationSnapshot(afterString, pool);

    diffReports(beforeString, afterString);

    configChangePlausibilityTest(configBefore, configAfter);

    if (runE2E) e2eTest(pool);
    return (configBefore, configAfter);
  }

  function configChangePlausibilityTest(
    ReserveConfig[] memory configBefore,
    ReserveConfig[] memory configAfter
  ) public view {
    uint256 configsBeforeLength = configBefore.length;
    for (uint256 i = 0; i < configAfter.length; i++) {
      // assets are usually not permanently unlisted, so the expectation is there will only be addition
      // if config existed before
      if (i < configsBeforeLength) {
        // borrow increase should only happen on assets with borrowing enabled
        // unless it is setting a borrow cap for the first time
        if (
          configBefore[i].borrowCap < configAfter[i].borrowCap && configBefore[i].borrowCap != 0
        ) {
          require(configAfter[i].borrowingEnabled, 'PL_BORROW_CAP_BORROW_DISABLED');
        }
      } else {
        // at least newly listed assets should never have a supply cap exceeding total supply
        uint256 totalSupply = IERC20(configAfter[i].underlying).totalSupply();
        require(
          configAfter[i].supplyCap / 1e2 <=
            totalSupply / IERC20Metadata(configAfter[i].underlying).decimals(),
          'PL_SUPPLY_CAP_GT_TOTAL_SUPPLY'
        );
      }
      // borrow cap should never exceed supply cap
      if (
        configAfter[i].borrowCap != 0 &&
        configAfter[i].underlying != AaveV3EthereumAssets.GHO_UNDERLYING // GHO is the exclusion from the rule
      ) {
        console.log(configAfter[i].underlying);
        require(configAfter[i].borrowCap <= configAfter[i].supplyCap, 'PL_SUPPLY_LT_BORROW');
      }
    }
  }

  /**
   * @dev Generates a markdown compatible snapshot of the whole pool configuration into `/reports`.
   * @param reportName filename suffix for the generated reports.
   * @param pool the pool to be snapshot
   * @return ReserveConfig[] list of configs
   */
  function createConfigurationSnapshot(
    string memory reportName,
    IPool pool
  ) public override returns (ReserveConfig[] memory) {
    return createConfigurationSnapshot(reportName, pool, true, true, true, true);
  }

  function createConfigurationSnapshot(
    string memory reportName,
    IPool pool,
    bool reserveConfigs,
    bool strategyConfigs,
    bool eModeConigs,
    bool poolConfigs
  ) public override returns (ReserveConfig[] memory) {
    return snapshotHelper.createConfigurationSnapshot(
      reportName,
      pool,
      reserveConfigs,
      strategyConfigs,
      eModeConigs,
      poolConfigs
    );
  }

  /**
   * @dev Makes a e2e test including withdrawals/borrows and supplies to various reserves.
   * @param pool the pool that should be tested
   */
  function e2eTest(IPool pool) public {
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    ReserveConfig memory collateralConfig = _getGoodCollateral(configs);
    uint256 snapshot = vm.snapshot();
    for (uint256 i; i < configs.length; i++) {
      if (_includeInE2e(configs[i])) {
        e2eTestAsset(pool, collateralConfig, configs[i]);
        vm.revertTo(snapshot);
      } else {
        console.log('E2E: TestAsset %s SKIPPED', configs[i].symbol);
      }
    }
  }

  function e2eTestAsset(
    IPool pool,
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
    uint256 collateralAssetAmount = _getTokenAmountByDollarValue(pool, collateralConfig, 100000);
    uint256 testAssetAmount = _getTokenAmountByDollarValue(pool, testAssetConfig, 1000);

    // remove caps as they should not prevent testing
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IPoolConfigurator poolConfigurator = IPoolConfigurator(addressesProvider.getPoolConfigurator());
    vm.startPrank(addressesProvider.getACLAdmin());
    if (collateralConfig.supplyCap != 0)
      poolConfigurator.setSupplyCap(collateralConfig.underlying, 0);
    if (testAssetConfig.supplyCap != 0)
      poolConfigurator.setSupplyCap(testAssetConfig.underlying, 0);
    if (testAssetConfig.borrowCap != 0)
      poolConfigurator.setBorrowCap(testAssetConfig.underlying, 0);
    vm.stopPrank();

    // GHO is a special case as it cannot be supplied
    if (testAssetConfig.underlying == AaveV3EthereumAssets.GHO_UNDERLYING) {
      _deposit(collateralConfig, pool, collateralSupplier, collateralAssetAmount);
      uint256 snapshot = vm.snapshot();
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
    } else {
      _deposit(collateralConfig, pool, collateralSupplier, collateralAssetAmount);
      _deposit(testAssetConfig, pool, testAssetSupplier, testAssetAmount);
      uint256 snapshot = vm.snapshot();
      // test withdrawal
      _withdraw(testAssetConfig, pool, testAssetSupplier, testAssetAmount / 2);
      _withdraw(testAssetConfig, pool, testAssetSupplier, type(uint256).max);
      vm.revertTo(snapshot);
      // test variable borrowing
      if (testAssetConfig.borrowingEnabled) {
        if (
          (testAssetConfig.borrowCap * 10 ** testAssetConfig.decimals) <
          IERC20(testAssetConfig.variableDebtToken).totalSupply() + testAssetAmount
        ) {
          console.log('Skip Borrowing: %s, borrow cap fully utilized', testAssetConfig.symbol);
          return;
        }
        _e2eTestBorrowRepay(pool, collateralSupplier, testAssetConfig, testAssetAmount, false);
        vm.revertTo(snapshot);
        // test stable borrowing
        if (testAssetConfig.stableBorrowRateEnabled) {
          _e2eTestBorrowRepay(pool, collateralSupplier, testAssetConfig, testAssetAmount, true);
          vm.revertTo(snapshot);
        }
      }
    }
  }

  /**
   * Reserves that are frozen or not active should not be included in e2e test suite
   */
  function _includeInE2e(ReserveConfig memory config) internal pure returns (bool) {
    return !config.isFrozen && config.isActive && !config.isPaused;
  }

  function _getTokenAmountByDollarValue(
    IPool pool,
    ReserveConfig memory config,
    uint256 dollarValue
  ) internal view returns (uint256) {
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    uint256 latestAnswer = oracle.getAssetPrice(config.underlying);
    return (dollarValue * 10 ** (8 + config.decimals)) / latestAnswer;
  }

  function _e2eTestBorrowRepay(
    IPool pool,
    address borrower,
    ReserveConfig memory testAssetConfig,
    uint256 amount,
    bool stable
  ) internal {
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
  }

  /**
   * @dev returns a "good" collateral in the list that cannot be borrowed in stable mode
   */
  function _getGoodCollateral(
    ReserveConfig[] memory configs
  ) private pure returns (ReserveConfig memory config) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (
        // not frozen etc
        _includeInE2e(configs[i]) &&
        // usable as collateral
        configs[i].usageAsCollateralEnabled &&
        // not stable borrowable as this makes testing stable borrowing unnecessary hard to reason about
        !configs[i].stableBorrowRateEnabled &&
        // not isolated asset as we can only borrow stablecoins against it
        configs[i].debtCeiling == 0
      ) return configs[i];
    }
    revert('ERROR: No usable collateral found');
  }

  function _deposit(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount
  ) internal {
    require(!config.isFrozen, 'DEPOSIT(): FROZEN_RESERVE');
    require(config.isActive, 'DEPOSIT(): INACTIVE_RESERVE');
    require(!config.isPaused, 'DEPOSIT(): PAUSED_RESERVE');
    vm.startPrank(user);
    uint256 aTokenBefore = IERC20(config.aToken).balanceOf(user);
    deal2(config.underlying, user, amount);
    IERC20(config.underlying).forceApprove(address(pool), amount);
    console.log('SUPPLY: %s, Amount: %s', config.symbol, amount);
    pool.deposit(config.underlying, amount, user, 0);
    uint256 aTokenAfter = IERC20(config.aToken).balanceOf(user);
    assertApproxEqAbs(aTokenAfter, aTokenBefore + amount, 1);
    vm.stopPrank();
  }

  function _withdraw(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount
  ) internal returns (uint256) {
    vm.startPrank(user);
    uint256 aTokenBefore = IERC20(config.aToken).balanceOf(user);
    uint256 amountOut = pool.withdraw(config.underlying, amount, user);
    console.log('WITHDRAW: %s, Amount: %s', config.symbol, amountOut);
    uint256 aTokenAfter = IERC20(config.aToken).balanceOf(user);
    if (aTokenBefore < amount) {
      require(aTokenAfter == 0, '_withdraw(): DUST_AFTER_WITHDRAW_ALL');
    } else {
      assertApproxEqAbs(aTokenAfter, aTokenBefore - amount, 1);
    }
    vm.stopPrank();
    return amountOut;
  }

  function _borrow(
    ReserveConfig memory config,
    IPool pool,
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
    assertApproxEqAbs(debtAfter, debtBefore + amount, 1);
    vm.stopPrank();
  }

  function _repay(
    ReserveConfig memory config,
    IPool pool,
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

  function _writeEModeConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) internal override {
    return snapshotHelper.writeEModeConfigs(
      path,
      configs,
      pool
    );
  }

  function _writeStrategyConfigs(string memory path, ReserveConfig[] memory configs) internal override {
    return snapshotHelper.writeStrategyConfigs(path, configs);
  }

  function _writeReserveConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) internal override {
    return snapshotHelper.writeReserveConfigs(path, configs, pool);
  }

  function _writePoolConfiguration(string memory path, IPool pool) internal override {
    return snapshotHelper.writePoolConfiguration(path, pool);
  }

  function _getReservesConfigs(IPool pool) internal view override returns (ReserveConfig[] memory) {
    return snapshotHelper.getReservesConfigs(pool);
  }

  function _getStructReserveTokens(
    IPoolDataProvider pdp,
    address underlyingAddress
  ) internal view override returns (ReserveTokens memory) {
    return snapshotHelper.getStructReserveTokens(pdp, underlyingAddress);
  }

  function _getStructReserveConfig(
    IPool pool,
    IPoolDataProvider.TokenData memory reserve
  ) internal view virtual returns (ReserveConfig memory) {
    return snapshotHelper.getStructReserveConfig(pool, reserve);
  }

  // TODO This should probably be simplified with assembly, too much boilerplate
  function _clone(ReserveConfig memory config) internal pure override returns (ReserveConfig memory) {
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
        liquidationProtocolFee: config.liquidationProtocolFee,
        reserveFactor: config.reserveFactor,
        usageAsCollateralEnabled: config.usageAsCollateralEnabled,
        borrowingEnabled: config.borrowingEnabled,
        interestRateStrategy: config.interestRateStrategy,
        stableBorrowRateEnabled: config.stableBorrowRateEnabled,
        isPaused: config.isPaused,
        isActive: config.isActive,
        isFrozen: config.isFrozen,
        isSiloed: config.isSiloed,
        isBorrowableInIsolation: config.isBorrowableInIsolation,
        isFlashloanable: config.isFlashloanable,
        supplyCap: config.supplyCap,
        borrowCap: config.borrowCap,
        debtCeiling: config.debtCeiling,
        eModeCategory: config.eModeCategory,
        virtualAccActive: config.virtualAccActive,
        virtualBalance: config.virtualBalance,
        aTokenUnderlyingBalance: config.aTokenUnderlyingBalance
      });
  }

  function _findReserveConfig(
    ReserveConfig[] memory configs,
    address underlying
  ) internal pure override returns (ReserveConfig memory) {
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
  ) internal pure override returns (ReserveConfig memory) {
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
    console.log('Liquidation protocol fee ', config.liquidationProtocolFee);
    console.log('Reserve Factor ', config.reserveFactor);
    console.log('Usage as collateral enabled ', (config.usageAsCollateralEnabled) ? 'Yes' : 'No');
    console.log('Borrowing enabled ', (config.borrowingEnabled) ? 'Yes' : 'No');
    console.log('Stable borrow rate enabled ', (config.stableBorrowRateEnabled) ? 'Yes' : 'No');
    console.log('Supply cap ', config.supplyCap);
    console.log('Borrow cap ', config.borrowCap);
    console.log('Debt ceiling ', config.debtCeiling);
    console.log('eMode category ', config.eModeCategory);
    console.log('Interest rate strategy ', config.interestRateStrategy);
    console.log('Is active ', (config.isActive) ? 'Yes' : 'No');
    console.log('Is frozen ', (config.isFrozen) ? 'Yes' : 'No');
    console.log('Is siloed ', (config.isSiloed) ? 'Yes' : 'No');
    console.log('Is borrowable in isolation ', (config.isBorrowableInIsolation) ? 'Yes' : 'No');
    console.log('Is flashloanable ', (config.isFlashloanable) ? 'Yes' : 'No');
    console.log('Is virtual accounting active ', (config.virtualAccActive) ? 'Yes' : 'No');
    console.log('Virtual balance ', config.virtualBalance);
    console.log('-----');
    console.log('-----');
  }

  function _validateReserveConfig(
    ReserveConfig memory expectedConfig,
    ReserveConfig[] memory allConfigs
  ) internal pure override {
    ReserveConfig memory config = _findReserveConfig(allConfigs, expectedConfig.underlying);
    require(
      keccak256(bytes(config.symbol)) == keccak256(bytes(expectedConfig.symbol)),
      '_validateReserveConfig() : INVALID_SYMBOL'
    );
    require(
      config.underlying == expectedConfig.underlying,
      '_validateReserveConfig() : INVALID_UNDERLYING'
    );
    require(config.decimals == expectedConfig.decimals, '_validateReserveConfig: INVALID_DECIMALS');
    require(config.ltv == expectedConfig.ltv, '_validateReserveConfig: INVALID_LTV');
    require(
      config.liquidationThreshold == expectedConfig.liquidationThreshold,
      '_validateReserveConfig: INVALID_LIQ_THRESHOLD'
    );
    require(
      config.liquidationBonus == expectedConfig.liquidationBonus,
      '_validateReserveConfig: INVALID_LIQ_BONUS'
    );
    require(
      config.liquidationProtocolFee == expectedConfig.liquidationProtocolFee,
      '_validateReserveConfig: INVALID_LIQUIDATION_PROTOCOL_FEE'
    );
    require(
      config.reserveFactor == expectedConfig.reserveFactor,
      '_validateReserveConfig: INVALID_RESERVE_FACTOR'
    );

    require(
      config.usageAsCollateralEnabled == expectedConfig.usageAsCollateralEnabled,
      '_validateReserveConfig: INVALID_USAGE_AS_COLLATERAL'
    );
    require(
      config.borrowingEnabled == expectedConfig.borrowingEnabled,
      '_validateReserveConfig: INVALID_BORROWING_ENABLED'
    );
    require(
      config.stableBorrowRateEnabled == expectedConfig.stableBorrowRateEnabled,
      '_validateReserveConfig: INVALID_STABLE_BORROW_ENABLED'
    );
    require(
      config.isActive == expectedConfig.isActive,
      '_validateReserveConfig: INVALID_IS_ACTIVE'
    );
    require(
      config.isFrozen == expectedConfig.isFrozen,
      '_validateReserveConfig: INVALID_IS_FROZEN'
    );
    require(
      config.isSiloed == expectedConfig.isSiloed,
      '_validateReserveConfig: INVALID_IS_SILOED'
    );
    require(
      config.isBorrowableInIsolation == expectedConfig.isBorrowableInIsolation,
      '_validateReserveConfig: INVALID_IS_BORROWABLE_IN_ISOLATION'
    );
    require(
      config.isFlashloanable == expectedConfig.isFlashloanable,
      '_validateReserveConfig: INVALID_IS_FLASHLOANABLE'
    );
    require(
      config.supplyCap == expectedConfig.supplyCap,
      '_validateReserveConfig: INVALID_SUPPLY_CAP'
    );
    require(
      config.borrowCap == expectedConfig.borrowCap,
      '_validateReserveConfig: INVALID_BORROW_CAP'
    );
    require(
      config.debtCeiling == expectedConfig.debtCeiling,
      '_validateReserveConfig: INVALID_DEBT_CEILING'
    );
    require(
      config.eModeCategory == expectedConfig.eModeCategory,
      '_validateReserveConfig: INVALID_EMODE_CATEGORY'
    );
    require(
      config.interestRateStrategy == expectedConfig.interestRateStrategy,
      '_validateReserveConfig: INVALID_INTEREST_RATE_STRATEGY'
    );
  }

  function getIsVirtualAccActive(
    DataTypes.ReserveConfigurationMap memory configuration
  ) external pure returns (bool) {
    return configuration.getIsVirtualAccActive();
  }

  // TODO: deprecated, remove it later
  function _validateInterestRateStrategy(
    address interestRateStrategyAddress,
    address expectedStrategy,
    InterestStrategyValues memory expectedStrategyValues
  ) internal view {
    ILegacyDefaultInterestRateStrategy strategy = ILegacyDefaultInterestRateStrategy(
      interestRateStrategyAddress
    );

    require(
      address(strategy) == expectedStrategy,
      '_validateInterestRateStrategy() : INVALID_STRATEGY_ADDRESS'
    );

    require(
      strategy.OPTIMAL_USAGE_RATIO() == expectedStrategyValues.optimalUsageRatio,
      '_validateInterestRateStrategy() : INVALID_OPTIMAL_RATIO'
    );
    require(
      strategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO() ==
        expectedStrategyValues.optimalStableToTotalDebtRatio,
      '_validateInterestRateStrategy() : INVALID_OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO'
    );
    require(
      address(strategy.ADDRESSES_PROVIDER()) == expectedStrategyValues.addressesProvider,
      '_validateInterestRateStrategy() : INVALID_ADDRESSES_PROVIDER'
    );
    require(
      strategy.getBaseVariableBorrowRate() == expectedStrategyValues.baseVariableBorrowRate,
      '_validateInterestRateStrategy() : INVALID_BASE_VARIABLE_BORROW'
    );
    require(
      strategy.getBaseStableBorrowRate() == expectedStrategyValues.baseStableBorrowRate,
      '_validateInterestRateStrategy() : INVALID_BASE_STABLE_BORROW'
    );
    require(
      strategy.getStableRateSlope1() == expectedStrategyValues.stableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_1'
    );
    require(
      strategy.getStableRateSlope2() == expectedStrategyValues.stableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_2'
    );
    require(
      strategy.getVariableRateSlope1() == expectedStrategyValues.variableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_1'
    );
    require(
      strategy.getVariableRateSlope2() == expectedStrategyValues.variableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_2'
    );
  }
}
