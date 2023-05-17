// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import 'forge-std/StdJson.sol';
import 'forge-std/Test.sol';

struct ReserveTokens {
  address aToken;
  address stableDebtToken;
  address variableDebtToken;
}

contract CommonTestBase is Test {
  using stdJson for string;

  address public constant ETH_MOCK_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  address public constant EOA = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

  /**
   * @dev generates the diff between two reports
   */
  function diffReports(string memory reportBefore, string memory reportAfter) internal {
    string memory outPath = string(
      abi.encodePacked('./diffs/', reportBefore, '_', reportAfter, '.md')
    );
    string memory beforePath = string(abi.encodePacked('./reports/', reportBefore, '.json'));
    string memory afterPath = string(abi.encodePacked('./reports/', reportAfter, '.json'));

    string[] memory inputs = new string[](6);
    inputs[0] = 'npx';
    inputs[1] = '@bgd-labs/report-engine';
    inputs[2] = 'diff';
    inputs[3] = beforePath;
    inputs[4] = afterPath;
    inputs[5] = outPath;
    vm.ffi(inputs);
  }

  function ipfsHashFile(string memory filePath, bool upload) internal returns (bytes32) {
    string[] memory inputs = new string[](5);
    inputs[0] = 'aave-report-engine';
    inputs[1] = 'ipfs';
    inputs[2] = filePath;
    inputs[3] = '-u';
    inputs[4] = vm.toString(upload);
    bytes memory bs58Hash = vm.ffi(inputs);
    emit log_bytes(bs58Hash);
    return bytes32(bs58Hash);
  }

  function ipfsHashFile(string memory filePath) internal returns (bytes32) {
    return ipfsHashFile(filePath, false);
  }

  /**
   * @dev forwards time by x blocks
   */
  function _skipBlocks(uint128 blocks) internal {
    vm.roll(block.number + blocks);
    vm.warp(block.timestamp + blocks * 12); // assuming a block is around 12seconds
  }

  function _isInUint256Array(
    uint256[] memory haystack,
    uint256 needle
  ) internal pure returns (bool) {
    for (uint256 i = 0; i < haystack.length; i++) {
      if (haystack[i] == needle) return true;
    }
    return false;
  }

  function _isInAddressArray(
    address[] memory haystack,
    address needle
  ) internal pure returns (bool) {
    for (uint256 i = 0; i < haystack.length; i++) {
      if (haystack[i] == needle) return true;
    }
    return false;
  }
}
