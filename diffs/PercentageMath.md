diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/PercentageMath.sol b/src/dependencies/PercentageMath.sol
index 4a478e9..5b39c2e 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/PercentageMath.sol
+++ b/src/dependencies/PercentageMath.sol
@@ -1,7 +1,8 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
+// From commit https://github.com/aave/protocol-v2/commit/92a731ec2c536734924f5a55d3e6db0385b0c824
+pragma solidity >=0.6.12;
 
-import {Errors} from '../helpers/Errors.sol';
+import {Errors} from '../dependencies/Errors.sol';
 
 /**
  * @title PercentageMath library
