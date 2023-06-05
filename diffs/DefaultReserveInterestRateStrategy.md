diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/DefaultReserveInterestRateStrategy.sol b/src/dependencies/DefaultReserveInterestRateStrategy.sol
index 32ab6ee..4f793be 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/DefaultReserveInterestRateStrategy.sol
+++ b/src/dependencies/DefaultReserveInterestRateStrategy.sol
@@ -1,13 +1,13 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
-
-import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
-import {IReserveInterestRateStrategy} from '../../interfaces/IReserveInterestRateStrategy.sol';
-import {WadRayMath} from '../libraries/math/WadRayMath.sol';
-import {PercentageMath} from '../libraries/math/PercentageMath.sol';
-import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
-import {ILendingRateOracle} from '../../interfaces/ILendingRateOracle.sol';
-import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
+// From commit https://github.com/aave/protocol-v2/commit/5f817c7c09139585c7dbc18aef07380ab8148869
+pragma solidity >=0.6.12;
+
+import {SafeMath} from '../dependencies/SafeMath.sol';
+import {IReserveInterestRateStrategy} from '../dependencies/IReserveInterestRateStrategy.sol';
+import {WadRayMath} from '../dependencies/WadRayMath.sol';
+import {PercentageMath} from '../dependencies/PercentageMath.sol';
+import {ILendingPoolAddressesProvider, ILendingRateOracle} from 'aave-address-book/AaveV2.sol';
+import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
 
 /**
  * @title DefaultReserveInterestRateStrategy contract
