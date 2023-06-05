diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/Errors.sol b/src/dependencies/Errors.sol
index 2a938b6..c93085d 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/Errors.sol
+++ b/src/dependencies/Errors.sol
@@ -1,5 +1,6 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
+// From commit https://github.com/aave/protocol-v2/commit/92a731ec2c536734924f5a55d3e6db0385b0c824
+pragma solidity >=0.6.12;
 
 /**
  * @title Errors library
