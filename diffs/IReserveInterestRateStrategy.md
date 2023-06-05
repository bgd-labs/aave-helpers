diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/IReserveInterestRateStrategy.sol b/src/dependencies/IReserveInterestRateStrategy.sol
index 014d2ee..da59b02 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/IReserveInterestRateStrategy.sol
+++ b/src/dependencies/IReserveInterestRateStrategy.sol
@@ -1,5 +1,6 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
+// From commit https://github.com/aave/protocol-v2/commit/7f44a0c2422cf08290a7a35b5652b5ef43d4d22f
+pragma solidity >=0.6.12;
 
 /**
  * @title IReserveInterestRateStrategyInterface interface
