// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Test} from 'forge-std/Test.sol';
import {IAaveOracle, ILendingPool, ILendingPoolAddressesProvider, ILendingPoolConfigurator, IAaveProtocolDataProvider, TokenData, ILendingRateOracle, IDefaultInterestRateStrategy} from 'aave-address-book/AaveV2.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {AaveV2EthereumAMM} from 'aave-address-book/AaveV2EthereumAMM.sol';
import {ExtendedAggregatorV2V3Interface} from './interfaces/ExtendedAggregatorV2V3Interface.sol';
import {ReserveTokens} from './CommonTestBase.sol';
import {ProxyHelpers} from './ProxyHelpers.sol';
import {ReserveConfig, LocalVars} from './ProtocolV2TestBase.sol';

contract SnapshotHelpersV2 is Test {
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
    string memory path = string(abi.encodePacked('./reports/', reportName, '.json'));
    vm.writeFile(path, '{ "reserves": {}, "strategies": {}, "poolConfiguration": {} }');
    vm.serializeUint('root', 'chainId', block.chainid);
    ReserveConfig[] memory configs = getReservesConfigs(pool);
    ILendingPoolAddressesProvider addressesProvider = ILendingPoolAddressesProvider(
      pool.getAddressesProvider()
    );
    ILendingRateOracle oracle = ILendingRateOracle(addressesProvider.getLendingRateOracle());
    writeReserveConfigs(path, configs, pool, oracle);
    writeStrategyConfigs(path, configs);
    writePoolConfiguration(path, pool);

    return configs;
  }

  function writeStrategyConfigs(string memory path, ReserveConfig[] memory configs) public {
    // keys for json stringification
    string memory strategiesKey = 'stategies';
    string memory content = '{}';
    vm.serializeJson(strategiesKey, '{}');

    for (uint256 i = 0; i < configs.length; i++) {
      IDefaultInterestRateStrategy strategy = IDefaultInterestRateStrategy(
        configs[i].interestRateStrategy
      );
      string memory key = vm.toString(configs[i].underlying);
      vm.serializeJson(key, '{}');
      vm.serializeString(key, 'address', vm.toString(address(strategy)));
      vm.serializeString(key, 'stableRateSlope1', vm.toString(strategy.stableRateSlope1()));
      vm.serializeString(key, 'stableRateSlope2', vm.toString(strategy.stableRateSlope2()));
      vm.serializeString(
        key,
        'baseVariableBorrowRate',
        vm.toString(strategy.baseVariableBorrowRate())
      );
      vm.serializeString(key, 'variableRateSlope1', vm.toString(strategy.variableRateSlope1()));
      vm.serializeString(key, 'variableRateSlope2', vm.toString(strategy.variableRateSlope2()));
      vm.serializeString(
        key,
        'optimalUsageRatio',
        vm.toString(strategy.OPTIMAL_UTILIZATION_RATE())
      );
      string memory object = vm.serializeString(
        key,
        'maxExcessUsageRatio',
        vm.toString(strategy.EXCESS_UTILIZATION_RATE())
      );
      content = vm.serializeString(strategiesKey, key, object);
    }
    string memory output = vm.serializeString('root', 'strategies', content);
    vm.writeJson(output, path);
  }

  function writePoolConfiguration(string memory path, ILendingPool pool) public {
    // keys for json stringification
    string memory poolConfigKey = 'poolConfig';

    // addresses provider
    ILendingPoolAddressesProvider addressesProvider = ILendingPoolAddressesProvider(
      pool.getAddressesProvider()
    );
    vm.serializeAddress(poolConfigKey, 'poolAddressesProvider', address(addressesProvider));

    // oracle
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    vm.serializeAddress(poolConfigKey, 'oracle', address(oracle));

    // pool configurator
    ILendingPoolConfigurator configurator = ILendingPoolConfigurator(
      addressesProvider.getLendingPoolConfigurator()
    );
    vm.serializeAddress(poolConfigKey, 'poolConfigurator', address(configurator));
    vm.serializeAddress(
      poolConfigKey,
      'poolConfiguratorImpl',
      ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, address(configurator))
    );
    address lendingPoolCollateralManager = addressesProvider.getLendingPoolCollateralManager();
    vm.serializeAddress(
      poolConfigKey,
      'lendingPoolCollateralManager',
      address(lendingPoolCollateralManager)
    );

    // PoolDataProvider
    IAaveProtocolDataProvider pdp = IAaveProtocolDataProvider(
      addressesProvider.getAddress(
        pool == AaveV2EthereumAMM.POOL
          ? bytes32(0x1000000000000000000000000000000000000000000000000000000000000000)
          : bytes32(0x0100000000000000000000000000000000000000000000000000000000000000)
      )
    );
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

  function writeReserveConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    ILendingPool pool,
    ILendingRateOracle rateOracle
  ) public {
    // keys for json stringification
    string memory reservesKey = 'reserves';
    string memory content = '{}';
    vm.serializeJson(reservesKey, '{}');

    ILendingPoolAddressesProvider addressesProvider = ILendingPoolAddressesProvider(
      pool.getAddressesProvider()
    );
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());

    for (uint256 i = 0; i < configs.length; i++) {
      ReserveConfig memory config = configs[i];
      ExtendedAggregatorV2V3Interface assetOracle = ExtendedAggregatorV2V3Interface(
        oracle.getSourceOfAsset(config.underlying)
      );

      string memory key = vm.toString(config.underlying);
      vm.serializeJson(key, '{}');
      vm.serializeString(key, 'symbol', config.symbol);
      vm.serializeString(
        key,
        'baseStableBorrowRate',
        vm.toString(rateOracle.getMarketBorrowRate(config.underlying))
      );
      vm.serializeUint(key, 'ltv', config.ltv);
      vm.serializeUint(key, 'liquidationThreshold', config.liquidationThreshold);
      vm.serializeUint(key, 'liquidationBonus', config.liquidationBonus);
      vm.serializeUint(key, 'reserveFactor', config.reserveFactor);
      vm.serializeUint(key, 'decimals', config.decimals);
      vm.serializeBool(key, 'usageAsCollateralEnabled', config.usageAsCollateralEnabled);
      vm.serializeBool(key, 'borrowingEnabled', config.borrowingEnabled);
      vm.serializeBool(key, 'stableBorrowRateEnabled', config.stableBorrowRateEnabled);
      vm.serializeBool(key, 'isActive', config.isActive);
      vm.serializeBool(key, 'isFrozen', config.isFrozen);
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

  function getReservesConfigs(ILendingPool pool) public view returns (ReserveConfig[] memory) {
    ILendingPoolAddressesProvider addressesProvider = ILendingPoolAddressesProvider(
      pool.getAddressesProvider()
    );
    IAaveProtocolDataProvider poolDataProvider = IAaveProtocolDataProvider(
      addressesProvider.getAddress(
        pool == AaveV2EthereumAMM.POOL
          ? bytes32(0x1000000000000000000000000000000000000000000000000000000000000000)
          : bytes32(0x0100000000000000000000000000000000000000000000000000000000000000)
      )
    );
    LocalVars memory vars;

    vars.reserves = poolDataProvider.getAllReservesTokens();

    vars.configs = new ReserveConfig[](vars.reserves.length);

    for (uint256 i = 0; i < vars.reserves.length; i++) {
      vars.configs[i] = getStructReserveConfig(pool, poolDataProvider, vars.reserves[i]);
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

  function getStructReserveConfig(
    ILendingPool pool,
    IAaveProtocolDataProvider pdp,
    TokenData memory reserve
  ) public view virtual returns (ReserveConfig memory) {
    ReserveConfig memory localConfig;
    (
      uint256 decimals,
      uint256 ltv,
      uint256 liquidationThreshold,
      uint256 liquidationBonus,
      uint256 reserveFactor,
      bool usageAsCollateralEnabled,
      bool borrowingEnabled,
      bool stableBorrowRateEnabled,
      bool isActive,
      bool isFrozen
    ) = pdp.getReserveConfigurationData(reserve.tokenAddress);
    localConfig.symbol = reserve.symbol;
    localConfig.underlying = reserve.tokenAddress;
    localConfig.decimals = decimals;
    localConfig.ltv = ltv;
    localConfig.liquidationThreshold = liquidationThreshold;
    localConfig.liquidationBonus = liquidationBonus;
    localConfig.reserveFactor = reserveFactor;
    localConfig.usageAsCollateralEnabled = usageAsCollateralEnabled;
    localConfig.borrowingEnabled = borrowingEnabled;
    localConfig.stableBorrowRateEnabled = stableBorrowRateEnabled;
    localConfig.interestRateStrategy = pool
      .getReserveData(reserve.tokenAddress)
      .interestRateStrategyAddress;
    localConfig.isActive = isActive;
    localConfig.isFrozen = isFrozen;

    return localConfig;
  }

  function getStructReserveTokens(
    IAaveProtocolDataProvider pdp,
    address underlyingAddress
  ) public view returns (ReserveTokens memory) {
    ReserveTokens memory reserveTokens;
    (reserveTokens.aToken, reserveTokens.stableDebtToken, reserveTokens.variableDebtToken) = pdp
      .getReserveTokensAddresses(underlyingAddress);

    return reserveTokens;
  }
}
