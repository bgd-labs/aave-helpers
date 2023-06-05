diff --git a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/SafeMath.sol b/src/dependencies/SafeMath.sol
index 76320f6..2555cf4 100644
--- a/commit-5f817c7c09139585c7dbc18aef07380ab8148869/SafeMath.sol
+++ b/src/dependencies/SafeMath.sol
@@ -1,5 +1,6 @@
 // SPDX-License-Identifier: agpl-3.0
-pragma solidity 0.6.12;
+// From commit https://github.com/aave/protocol-v2/commit/8c03180f89eea25e98356b80d8187cb0f12f29cd
+pragma solidity >=0.6.12;
 
 /**
  * @dev Wrappers over Solidity's arithmetic operations with added overflow
