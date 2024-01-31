// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WithChainIdValidation, EthereumScript} from './ScriptUtils.sol';
import {GovV3Helpers, IPayloadsControllerCore} from './GovV3Helpers.sol';

contract LetMeJustHaveSome {
  string public name = 'some';
}

abstract contract WithChainIdValidationAndPayloads is WithChainIdValidation {
  function getPayloads() public view virtual returns (bytes[] memory);
}

abstract contract WithChainIdValidationAndPayloadSimple is WithChainIdValidationAndPayloads {
  bytes public payloadCode;

  constructor(bytes memory code) {
    payloadCode = code;
  }

  function getPayloads() public view override returns (bytes[] memory) {
    bytes[] memory payloadsCode = new bytes[](1);
    payloadsCode[0] = payloadCode;
    return payloadsCode;
  }
}

abstract contract DeployPayloads is WithChainIdValidationAndPayloads {
  function run() external broadcast {
    bytes[] memory payloadsCode = getPayloads();

    // deploy payloads
    address[] memory payloadsAddresses = new address[](payloadsCode.length);
    for (uint256 i = 0; i < payloadsCode.length; i++) {
      payloadsAddresses[i] = GovV3Helpers.deployDeterministic(payloadsCode[i]);
    }

    // compose action
    IPayloadsControllerCore.ExecutionAction[]
      memory actions = new IPayloadsControllerCore.ExecutionAction[](payloadsCode.length);
    for (uint256 i = 0; i < payloadsCode.length; i++) {
      actions[i] = GovV3Helpers.buildAction(payloadsAddresses[i]);
    }

    // register action at payloadsController
    GovV3Helpers.createPayload(actions);
  }
}

contract DeploySomeSimple is
  WithChainIdValidationAndPayloadSimple(type(LetMeJustHaveSome).creationCode),
  EthereumScript
{}
