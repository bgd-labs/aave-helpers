// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @dev Mock contract that writes to storage slot 0 when called.
 * Used to test that _validateNoExecutorStorageChange catches storage writes.
 */
contract StorageWriter {
  function writeStorage() external {
    assembly {
      sstore(0, 42)
    }
  }
}
