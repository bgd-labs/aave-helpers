// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ISwapPayload {
  function execute() external;

  function deposit(address token, uint256 amount) external;
}
