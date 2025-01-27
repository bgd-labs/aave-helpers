// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {MiscEthereum} from 'aave-address-book/MiscEthereum.sol';
import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {AaveSwapper} from 'src/swaps/AaveSwapper.sol';
import {MiniSwapper} from 'src/swaps/MiniSwapper.sol';

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IConditionalOrder} from 'composable-cow/interfaces/IConditionalOrder.sol';

interface IComposableCoW {
  function getTradeableOrderWithSignature(
        address owner,
        IConditionalOrder.ConditionalOrderParams calldata params,
        bytes calldata offchainInput,
        bytes32[] calldata proof
    ) external view returns (GPv2Order.Data memory order, bytes memory signature);
}

struct TWAPData {
  IERC20 sellToken;
  IERC20 buyToken;
  address receiver;
  uint256 partSellAmount; // amount of sellToken to sell in each part
  uint256 minPartLimit; // max price to pay for a unit of buyToken denominated in sellToken
  uint256 t0;
  uint256 n;
  uint256 t;
  uint256 span;
  bytes32 appData;
}

contract TestTWAPSwap is Script {
  using SafeERC20 for IERC20;

  address public constant fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
  address public constant toToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // wETH
  address public constant recipient = 0x3765A685a401622C060E5D700D9ad89413363a91; // me
  uint256 public constant amount = 120e6;
  uint256 public constant numParts = 6;

  address public constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
  address public constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;
  address public constant COW_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  function run() external {
    vm.startBroadcast();

    // MiniSwapper(0x15135198E254259899e472C4D2Aa566fEC59077D).emergencyTokenTransfer(fromToken, recipient, amount);

    MiniSwapper swapper = new MiniSwapper(COMPOSABLE_COW);
    IERC20(fromToken).transfer(address(swapper), 120e6);

    swapper.twapSwap(
      TWAP_HANDLER,
      COW_RELAYER,
      fromToken, // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
      toToken, // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
      recipient, // 0x3765A685a401622C060E5D700D9ad89413363a91
      amount / numParts, // 120e6 / 6
      0.005 ether,
      block.timestamp,
      6,
      1 hours,
      0
    );

    vm.stopBroadcast();

    // TWAPData memory twapData = TWAPData(
    //   IERC20(fromToken),
    //   IERC20(toToken),
    //   recipient,
    //   amount / numParts,
    //   0.005 ether,
    //   1704456647,
    //   numParts,
    //   1 hours,
    //   0,
    //   ''
    // );
    // IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder
    //   .ConditionalOrderParams(
    //     IConditionalOrder(TWAP_HANDLER),
    //     'AaveSwapper-TWAP-Swap',
    //     abi.encode(twapData)
    //   );

    // bytes32[] memory proof = new bytes32[](0);
    // (GPv2Order.Data memory order, bytes memory sig) = IComposableCoW(COMPOSABLE_COW).getTradeableOrderWithSignature(
    //     0x15135198E254259899e472C4D2Aa566fEC59077D,
    //     params,
    //     "",
    //     proof
    // );

    // bytes32 domainSeparator = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    // bytes32 orderDigest = GPv2Order.hash(order, domainSeparator);    

    // MiniSwapper(0x15135198E254259899e472C4D2Aa566fEC59077D).isValidSignature(orderDigest, sig);
  }
}
