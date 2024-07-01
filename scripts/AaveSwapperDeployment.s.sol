// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {MiscEthereum} from 'aave-address-book/MiscEthereum.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';

import {AaveSwapper} from 'src/swaps/AaveSwapper.sol';

contract DeplyAaveSwapper is Script {
  function run() external {
    vm.startBroadcast();

    address aaveSwapper = address(new AaveSwapper(0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74));
    TransparentProxyFactory(MiscEthereum.TRANSPARENT_PROXY_FACTORY).create(
      aaveSwapper,
      MiscEthereum.PROXY_ADMIN,
      abi.encodeWithSelector(AaveSwapper.initialize.selector)
    );

    vm.stopBroadcast();
  }
}
