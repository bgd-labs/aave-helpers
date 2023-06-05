diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/WadRayMath.sol b/src/dependencies/WadRayMath.sol
index 29aa9c1..a62602a 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/WadRayMath.sol
+++ b/src/dependencies/WadRayMath.sol
@@ -1,7 +1,8 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
+// From commit https://github.com/aave/protocol-v2/commit/92a731ec2c536734924f5a55d3e6db0385b0c824
+pragma solidity >=0.6.12;
 
-import {Errors} from '../helpers/Errors.sol';
+import {Errors} from '../dependencies/Errors.sol';
 
 /**
  * @title WadRayMath library
