// SPDX-License-Identifier: MIT
// Modified from commit: https://github.com/LayerZero-Labs/LayerZero-v2/commit/4b2985921af42a778d26a48c9dee7b9644812cbd
pragma solidity ^0.8.0;

struct MessagingParams {
  uint32 dstEid;
  bytes32 receiver;
  bytes message;
  bytes options;
  bool payInLzToken;
}

struct MessagingReceipt {
  bytes32 guid;
  uint64 nonce;
  MessagingFee fee;
}

struct MessagingFee {
  uint256 nativeFee;
  uint256 lzTokenFee;
}

struct Origin {
  uint32 srcEid;
  bytes32 sender;
  uint64 nonce;
}

interface ILayerZeroEndpointV2 {
  function quote(
    MessagingParams calldata _params,
    address _sender
  ) external view returns (MessagingFee memory);

  function send(
    MessagingParams calldata _params,
    address _refundAddress
  ) external payable returns (MessagingReceipt memory);
}
