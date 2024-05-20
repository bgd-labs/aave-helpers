// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IAaveOracle, IPool, IPoolAddressesProvider, IPoolDataProvider, IDefaultInterestRateStrategy, DataTypes, IPoolConfigurator} from 'aave-address-book/AaveV3.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {ReserveConfiguration} from 'aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {ExtendedAggregatorV2V3Interface} from './interfaces/ExtendedAggregatorV2V3Interface.sol';
import {ProxyHelpers} from './ProxyHelpers.sol';
import {CommonTestBase, ReserveTokens} from './CommonTestBase.sol';
import {IDefaultInterestRateStrategyV2} from './dependencies/IDefaultInterestRateStrategyV2.sol';
import {ProtocolV3TestBase as TestBase, ReserveConfig, LocalVars} from './ProtocolV3TestBase.sol';

contract SnapshotHelpersV3 is CommonTestBase {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  function createConfigurationSnapshot(
    string memory reportName,
    IPool pool,
    bool reserveConfigs,
    bool strategyConfigs,
    bool eModeConigs,
    bool poolConfigs
  ) public returns (ReserveConfig[] memory) {
    string memory path = string(abi.encodePacked('./reports/', reportName, '.json'));
    // overwrite with empty json to later be extended
    vm.writeFile(
      path,
      '{ "eModes": {}, "reserves": {}, "strategies": {}, "poolConfiguration": {} }'
    );
    vm.serializeUint('root', 'chainId', block.chainid);
    ReserveConfig[] memory configs = getReservesConfigs(pool);
    if (reserveConfigs) writeReserveConfigs(path, configs, pool);
    if (strategyConfigs) writeStrategyConfigs(path, configs);
    if (eModeConigs) writeEModeConfigs(path, configs, pool);
    if (poolConfigs) writePoolConfiguration(path, pool);

    return configs;
  }

  function writeEModeConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) public {
    // keys for json stringification
    string memory eModesKey = 'emodes';
    string memory content = '{}';
    vm.serializeJson(eModesKey, '{}');

    uint256[] memory usedCategories = new uint256[](configs.length);
    for (uint256 i = 0; i < configs.length; i++) {
      if (!_isInUint256Array(usedCategories, configs[i].eModeCategory)) {
        usedCategories[i] = configs[i].eModeCategory;
        DataTypes.EModeCategory memory category = pool.getEModeCategoryData(
          uint8(configs[i].eModeCategory)
        );
        string memory key = vm.toString(configs[i].eModeCategory);
        vm.serializeJson(key, '{}');
        vm.serializeUint(key, 'eModeCategory', configs[i].eModeCategory);
        vm.serializeString(key, 'label', category.label);
        vm.serializeUint(key, 'ltv', category.ltv);
        vm.serializeUint(key, 'liquidationThreshold', category.liquidationThreshold);
        vm.serializeUint(key, 'liquidationBonus', category.liquidationBonus);
        string memory object = vm.serializeAddress(key, 'priceSource', category.priceSource);
        content = vm.serializeString(eModesKey, key, object);
      }
    }
    string memory output = vm.serializeString('root', 'eModes', content);
    vm.writeJson(output, path);
  }

  function writeStrategyConfigs(string memory path, ReserveConfig[] memory configs) public {
    // keys for json stringification
    string memory strategiesKey = 'stategies';
    string memory content = '{}';
    vm.serializeJson(strategiesKey, '{}');

    for (uint256 i = 0; i < configs.length; i++) {
      IDefaultInterestRateStrategyV2 strategyV2 = IDefaultInterestRateStrategyV2(
        configs[i].interestRateStrategy
      );
      IDefaultInterestRateStrategy strategyV1 = IDefaultInterestRateStrategy(
        configs[i].interestRateStrategy
      );
      address asset = configs[i].underlying;
      string memory key = vm.toString(asset);
      vm.serializeJson(key, '{}');
      vm.serializeString(key, 'address', vm.toString(configs[i].interestRateStrategy));
      string memory object;
      try strategyV1.getVariableRateSlope1() {
        vm.serializeString(
          key,
          'baseStableBorrowRate',
          vm.toString(strategyV1.getBaseStableBorrowRate())
        );
        vm.serializeString(key, 'stableRateSlope1', vm.toString(strategyV1.getStableRateSlope1()));
        vm.serializeString(key, 'stableRateSlope2', vm.toString(strategyV1.getStableRateSlope2()));
        vm.serializeString(
          key,
          'baseVariableBorrowRate',
          vm.toString(strategyV1.getBaseVariableBorrowRate())
        );
        vm.serializeString(
          key,
          'variableRateSlope1',
          vm.toString(strategyV1.getVariableRateSlope1())
        );
        vm.serializeString(
          key,
          'variableRateSlope2',
          vm.toString(strategyV1.getVariableRateSlope2())
        );
        vm.serializeString(
          key,
          'optimalStableToTotalDebtRatio',
          vm.toString(strategyV1.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO())
        );
        vm.serializeString(
          key,
          'maxExcessStableToTotalDebtRatio',
          vm.toString(strategyV1.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO())
        );
        vm.serializeString(key, 'optimalUsageRatio', vm.toString(strategyV1.OPTIMAL_USAGE_RATIO()));
        object = vm.serializeString(
          key,
          'maxExcessUsageRatio',
          vm.toString(strategyV1.MAX_EXCESS_USAGE_RATIO())
        );
      } catch {
        vm.serializeString(
          key,
          'baseVariableBorrowRate',
          vm.toString(strategyV2.getBaseVariableBorrowRate(asset))
        );
        vm.serializeString(
          key,
          'variableRateSlope1',
          vm.toString(strategyV2.getVariableRateSlope1(asset))
        );
        vm.serializeString(
          key,
          'variableRateSlope2',
          vm.toString(strategyV2.getVariableRateSlope2(asset))
        );
        vm.serializeString(
          key,
          'maxVariableBorrowRate',
          vm.toString(strategyV2.getMaxVariableBorrowRate(asset))
        );
        object = vm.serializeString(
          key,
          'optimalUsageRatio',
          vm.toString(strategyV2.getOptimalUsageRatio(asset))
        );
      }
      content = vm.serializeString(strategiesKey, key, object);
    }
    string memory output = vm.serializeString('root', 'strategies', content);
    vm.writeJson(output, path);
  }

  function writeReserveConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) public {
    // keys for json stringification
    string memory reservesKey = 'reserves';
    string memory content = '{}';
    vm.serializeJson(reservesKey, '{}');

    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    for (uint256 i = 0; i < configs.length; i++) {
      ReserveConfig memory config = configs[i];
      ExtendedAggregatorV2V3Interface assetOracle = ExtendedAggregatorV2V3Interface(
        oracle.getSourceOfAsset(config.underlying)
      );
      DataTypes.ReserveData memory reserveData = pool.getReserveData(config.underlying);

      string memory key = vm.toString(config.underlying);
      vm.serializeJson(key, '{}');
      vm.serializeString(key, 'symbol', config.symbol);
      vm.serializeUint(key, 'ltv', config.ltv);
      vm.serializeUint(key, 'liquidationThreshold', config.liquidationThreshold);
      vm.serializeUint(key, 'liquidationBonus', config.liquidationBonus);
      vm.serializeUint(key, 'liquidationProtocolFee', config.liquidationProtocolFee);
      vm.serializeUint(key, 'reserveFactor', config.reserveFactor);
      vm.serializeUint(key, 'decimals', config.decimals);
      vm.serializeUint(key, 'borrowCap', config.borrowCap);
      vm.serializeUint(key, 'supplyCap', config.supplyCap);
      vm.serializeUint(key, 'debtCeiling', config.debtCeiling);
      vm.serializeUint(key, 'eModeCategory', config.eModeCategory);
      vm.serializeUint(key, 'liquidityIndex', reserveData.liquidityIndex);
      vm.serializeUint(key, 'currentLiquidityRate', reserveData.currentLiquidityRate);
      vm.serializeUint(key, 'variableBorrowIndex', reserveData.variableBorrowIndex);
      vm.serializeUint(key, 'currentVariableBorrowRate', reserveData.currentVariableBorrowRate);
      vm.serializeBool(key, 'usageAsCollateralEnabled', config.usageAsCollateralEnabled);
      vm.serializeBool(key, 'borrowingEnabled', config.borrowingEnabled);
      vm.serializeBool(key, 'stableBorrowRateEnabled', config.stableBorrowRateEnabled);
      vm.serializeBool(key, 'isPaused', config.isPaused);
      vm.serializeBool(key, 'isActive', config.isActive);
      vm.serializeBool(key, 'isFrozen', config.isFrozen);
      vm.serializeBool(key, 'isSiloed', config.isSiloed);
      vm.serializeBool(key, 'isBorrowableInIsolation', config.isBorrowableInIsolation);
      vm.serializeBool(key, 'isFlashloanable', config.isFlashloanable);
      vm.serializeAddress(key, 'interestRateStrategy', config.interestRateStrategy);
      vm.serializeAddress(key, 'underlying', config.underlying);
      vm.serializeAddress(key, 'aToken', config.aToken);
      vm.serializeAddress(key, 'stableDebtToken', config.stableDebtToken);
      vm.serializeAddress(key, 'variableDebtToken', config.variableDebtToken);
      vm.serializeAddress(
        key,
        'aTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, config.aToken)
      );
      vm.serializeString(key, 'aTokenSymbol', IERC20Metadata(config.aToken).symbol());
      vm.serializeString(key, 'aTokenName', IERC20Metadata(config.aToken).name());
      vm.serializeAddress(
        key,
        'stableDebtTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
          vm,
          config.stableDebtToken
        )
      );
      vm.serializeString(
        key,
        'stableDebtTokenSymbol',
        IERC20Metadata(config.stableDebtToken).symbol()
      );
      vm.serializeString(key, 'stableDebtTokenName', IERC20Metadata(config.stableDebtToken).name());
      vm.serializeAddress(
        key,
        'variableDebtTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
          vm,
          config.variableDebtToken
        )
      );
      vm.serializeString(
        key,
        'variableDebtTokenSymbol',
        IERC20Metadata(config.variableDebtToken).symbol()
      );
      vm.serializeString(
        key,
        'variableDebtTokenName',
        IERC20Metadata(config.variableDebtToken).name()
      );
      vm.serializeAddress(key, 'oracle', address(assetOracle));
      if (address(assetOracle) != address(0)) {
        try assetOracle.description() returns (string memory name) {
          vm.serializeString(key, 'oracleDescription', name);
        } catch {
          try assetOracle.name() returns (string memory name) {
            vm.serializeString(key, 'oracleName', name);
          } catch {}
        }
        try assetOracle.decimals() returns (uint8 decimals) {
          vm.serializeUint(key, 'oracleDecimals', decimals);
        } catch {
          try assetOracle.DECIMALS() returns (uint8 decimals) {
            vm.serializeUint(key, 'oracleDecimals', decimals);
          } catch {}
        }
      }
      string memory out = vm.serializeUint(
        key,
        'oracleLatestAnswer',
        uint256(oracle.getAssetPrice(config.underlying))
      );
      content = vm.serializeString(reservesKey, key, out);
    }
    string memory output = vm.serializeString('root', 'reserves', content);
    vm.writeJson(output, path);
  }

  function writePoolConfiguration(string memory path, IPool pool) public {
    // keys for json stringification
    string memory poolConfigKey = 'poolConfig';

    // addresses provider
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    vm.serializeAddress(poolConfigKey, 'poolAddressesProvider', address(addressesProvider));

    // oracles
    vm.serializeAddress(poolConfigKey, 'oracle', addressesProvider.getPriceOracle());
    vm.serializeAddress(
      poolConfigKey,
      'priceOracleSentinel',
      addressesProvider.getPriceOracleSentinel()
    );

    // pool configurator
    IPoolConfigurator configurator = IPoolConfigurator(addressesProvider.getPoolConfigurator());
    vm.serializeAddress(poolConfigKey, 'poolConfigurator', address(configurator));
    vm.serializeAddress(
      poolConfigKey,
      'poolConfiguratorImpl',
      ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, address(configurator))
    );

    // PoolDataProvider
    IPoolDataProvider pdp = IPoolDataProvider(addressesProvider.getPoolDataProvider());
    vm.serializeAddress(poolConfigKey, 'protocolDataProvider', address(pdp));

    // pool
    vm.serializeAddress(
      poolConfigKey,
      'poolImpl',
      ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, address(pool))
    );
    string memory content = vm.serializeAddress(poolConfigKey, 'pool', address(pool));

    string memory output = vm.serializeString('root', 'poolConfig', content);
    vm.writeJson(output, path);
  }

  function getReservesConfigs(IPool pool) public view returns (ReserveConfig[] memory) {
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IPoolDataProvider poolDataProvider = IPoolDataProvider(addressesProvider.getPoolDataProvider());
    LocalVars memory vars;

    vars.reserves = poolDataProvider.getAllReservesTokens();

    vars.configs = new ReserveConfig[](vars.reserves.length);

    for (uint256 i = 0; i < vars.reserves.length; i++) {
      vars.configs[i] = getStructReserveConfig(pool, vars.reserves[i]);
      ReserveTokens memory reserveTokens = getStructReserveTokens(
        poolDataProvider,
        vars.configs[i].underlying
      );
      vars.configs[i].aToken = reserveTokens.aToken;
      vars.configs[i].variableDebtToken = reserveTokens.variableDebtToken;
      vars.configs[i].stableDebtToken = reserveTokens.stableDebtToken;
    }

    return vars.configs;
  }

  function getStructReserveTokens(
    IPoolDataProvider pdp,
    address underlyingAddress
  ) public view returns (ReserveTokens memory) {
    ReserveTokens memory reserveTokens;
    (reserveTokens.aToken, reserveTokens.stableDebtToken, reserveTokens.variableDebtToken) = pdp
      .getReserveTokensAddresses(underlyingAddress);

    return reserveTokens;
  }

  function getStructReserveConfig(
    IPool pool,
    IPoolDataProvider.TokenData memory reserve
  ) public view returns (ReserveConfig memory) {
    ReserveConfig memory localConfig;
    DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(
      reserve.tokenAddress
    );
    localConfig.interestRateStrategy = pool
      .getReserveData(reserve.tokenAddress)
      .interestRateStrategyAddress;
    (
      localConfig.ltv,
      localConfig.liquidationThreshold,
      localConfig.liquidationBonus,
      localConfig.decimals,
      localConfig.reserveFactor,
      localConfig.eModeCategory
    ) = configuration.getParams();
    (
      localConfig.isActive,
      localConfig.isFrozen,
      localConfig.borrowingEnabled,
      localConfig.stableBorrowRateEnabled,
      localConfig.isPaused
    ) = configuration.getFlags();
    localConfig.symbol = reserve.symbol;
    localConfig.underlying = reserve.tokenAddress;
    localConfig.usageAsCollateralEnabled = localConfig.liquidationThreshold != 0;
    localConfig.isSiloed = configuration.getSiloedBorrowing();
    (localConfig.borrowCap, localConfig.supplyCap) = configuration.getCaps();
    localConfig.debtCeiling = configuration.getDebtCeiling();
    localConfig.liquidationProtocolFee = configuration.getLiquidationProtocolFee();
    localConfig.isBorrowableInIsolation = configuration.getBorrowableInIsolation();

    localConfig.isFlashloanable = configuration.getFlashLoanEnabled();

    return localConfig;
  }
}
