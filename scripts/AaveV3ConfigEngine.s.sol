// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../src/ScriptUtils.sol';
import {AaveV3ConfigEngine} from '../src/v3-config-engine/AaveV3ConfigEngine.sol';
import {IV3RateStrategyFactory} from '../src/v3-config-engine/IV3RateStrategyFactory.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV3Optimism} from 'aave-address-book/AaveV3Optimism.sol';
import {AaveV3Arbitrum} from 'aave-address-book/AaveV3Arbitrum.sol';
import {AaveV3Polygon} from 'aave-address-book/AaveV3Polygon.sol';
import {AaveV3Avalanche} from 'aave-address-book/AaveV3Avalanche.sol';
import {AaveV3Metis} from 'aave-address-book/AaveV3Metis.sol';
import {IPool, IPoolConfigurator, IAaveOracle} from 'aave-address-book/AaveV3.sol';
import {CapsEngine} from '../src/v3-config-engine/libraries/CapsEngine.sol';
import {BorrowEngine} from '../src/v3-config-engine/libraries/BorrowEngine.sol';
import {CollateralEngine} from '../src/v3-config-engine/libraries/CollateralEngine.sol';
import {RateEngine} from '../src/v3-config-engine/libraries/RateEngine.sol';
import {PriceFeedEngine} from '../src/v3-config-engine/libraries/PriceFeedEngine.sol';
import {EModeEngine} from '../src/v3-config-engine/libraries/EModeEngine.sol';
import {ListingEngine} from '../src/v3-config-engine/libraries/ListingEngine.sol';

library DeployEngineEthLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Ethereum.POOL,
          AaveV3Ethereum.POOL_CONFIGURATOR,
          AaveV3Ethereum.ORACLE,
          AaveV3Ethereum.DEFAULT_A_TOKEN_IMPL_REV_1,
          AaveV3Ethereum.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_1,
          AaveV3Ethereum.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_1,
          AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Ethereum.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Ethereum.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

library DeployEngineOptLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Optimism.POOL,
          AaveV3Optimism.POOL_CONFIGURATOR,
          AaveV3Optimism.ORACLE,
          AaveV3Optimism.DEFAULT_A_TOKEN_IMPL_REV_2,
          AaveV3Optimism.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Optimism.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Optimism.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Optimism.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Optimism.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

library DeployEngineArbLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Arbitrum.POOL,
          AaveV3Arbitrum.POOL_CONFIGURATOR,
          AaveV3Arbitrum.ORACLE,
          AaveV3Arbitrum.DEFAULT_A_TOKEN_IMPL_REV_2,
          AaveV3Arbitrum.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Arbitrum.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Arbitrum.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Arbitrum.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Arbitrum.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

library DeployEnginePolLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Polygon.POOL,
          AaveV3Polygon.POOL_CONFIGURATOR,
          AaveV3Polygon.ORACLE,
          AaveV3Polygon.DEFAULT_A_TOKEN_IMPL_REV_2,
          AaveV3Polygon.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Polygon.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Polygon.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Polygon.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Polygon.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

library DeployEngineAvaLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Avalanche.POOL,
          AaveV3Avalanche.POOL_CONFIGURATOR,
          AaveV3Avalanche.ORACLE,
          AaveV3Avalanche.DEFAULT_A_TOKEN_IMPL_REV_2,
          AaveV3Avalanche.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Avalanche.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_2,
          AaveV3Avalanche.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Avalanche.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Avalanche.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

library DeployEngineMetLib {
  function deploy() internal returns (address) {
    AaveV3ConfigEngine.EngineLibraries memory engineLibraries = AaveV3ConfigEngine.EngineLibraries({
      listingEngine: Create2Utils._create2Deploy('v1', type(ListingEngine).creationCode),
      eModeEngine: Create2Utils._create2Deploy('v1', type(EModeEngine).creationCode),
      borrowEngine: Create2Utils._create2Deploy('v1', type(BorrowEngine).creationCode),
      collateralEngine: Create2Utils._create2Deploy('v1', type(CollateralEngine).creationCode),
      priceFeedEngine: Create2Utils._create2Deploy('v1', type(PriceFeedEngine).creationCode),
      rateEngine: Create2Utils._create2Deploy('v1', type(RateEngine).creationCode),
      capsEngine: Create2Utils._create2Deploy('v1', type(CapsEngine).creationCode)
    });

    return
      address(
        new AaveV3ConfigEngine(
          AaveV3Metis.POOL,
          AaveV3Metis.POOL_CONFIGURATOR,
          AaveV3Metis.ORACLE,
          AaveV3Metis.DEFAULT_A_TOKEN_IMPL_REV_1,
          AaveV3Metis.DEFAULT_VARIABLE_DEBT_TOKEN_IMPL_REV_1,
          AaveV3Metis.DEFAULT_STABLE_DEBT_TOKEN_IMPL_REV_1,
          AaveV3Metis.DEFAULT_INCENTIVES_CONTROLLER,
          address(AaveV3Metis.COLLECTOR),
          IV3RateStrategyFactory(AaveV3Metis.RATES_FACTORY),
          engineLibraries
        )
      );
  }
}

contract DeployEngineEth is EthereumScript {
  function run() external broadcast {
    DeployEngineEthLib.deploy();
  }
}

contract DeployEngineOpt is OptimismScript {
  function run() external broadcast {
    DeployEngineOptLib.deploy();
  }
}

contract DeployEngineArb is ArbitrumScript {
  function run() external broadcast {
    DeployEngineArbLib.deploy();
  }
}

contract DeployEnginePol is PolygonScript {
  function run() external broadcast {
    DeployEnginePolLib.deploy();
  }
}

contract DeployEngineAva is AvalancheScript {
  function run() external broadcast {
    DeployEngineAvaLib.deploy();
  }
}

contract DeployEngineMet is MetisScript {
  function run() external broadcast {
    DeployEngineMetLib.deploy();
  }
}