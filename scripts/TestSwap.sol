// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';

import {EthereumScript} from 'src/ScriptUtils.sol';
import {AaveSwapper} from 'src/swaps/AaveSwapper.sol';

// make test-swap
contract TestSwap is EthereumScript {
    uint256 public constant AMOUNT = 0.05 ether;
    uint256 public constant SLIPPAGE = 5000; // In BPS (basis points, ie: 100 is 1%)

    address public constant SWAPPER_INSTANCE = 0xCd04D93bEA13921DaD05240D577090b5AC36DfCA; // Your deployed swapper instance
    address public constant MILKMAN = 0x11C76AD590ABDFFCD980afEC9ad951B160F02797; // Milkman instance: 0x11C76AD590ABDFFCD980afEC9ad951B160F02797
    address public constant PRICE_CHECKER = 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c; // Chainlink Price Checker: 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c

    address public constant FROM_TOKEN = AaveV3EthereumAssets.WETH_UNDERLYING;
    address public constant TO_TOKEN = AaveV3EthereumAssets.rETH_UNDERLYING;
    address public constant FROM_ORACLE = AaveV3EthereumAssets.WETH_ORACLE;
    address public constant TO_ORACLE = 0xb031a238940e8051852b156f3efDc462fc34f37B; // rETH

    
    function run() external broadcast {
        IERC20(FROM_TOKEN).transfer(SWAPPER_INSTANCE, AMOUNT);

        AaveSwapper(SWAPPER_INSTANCE).swap(
            MILKMAN,
            PRICE_CHECKER,
            FROM_TOKEN,
            TO_TOKEN,
            FROM_ORACLE,
            TO_ORACLE,
            0x3765A685a401622C060E5D700D9ad89413363a91,
            AMOUNT,
            SLIPPAGE
        );
    }
}

// make cancel-swap
contract CancelSwap is EthereumScript {
    uint256 public constant AMOUNT = 0.05 ether;
    uint256 public constant SLIPPAGE = 5000; // In BPS (basis points, ie: 100 is 1%)

    address public constant SWAPPER_INSTANCE = 0xCd04D93bEA13921DaD05240D577090b5AC36DfCA; // Your deployed swapper instance
    address public constant TRADE_MILKMAN = 0xD1Fe23ADd41021E473f558B6D465c447a89f1759; // Contract that received funds after swap
    address public constant PRICE_CHECKER = 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c; // 

    address public constant FROM_TOKEN = AaveV3EthereumAssets.WETH_UNDERLYING;
    address public constant TO_TOKEN = AaveV3EthereumAssets.rETH_UNDERLYING;
    address public constant FROM_ORACLE = AaveV3EthereumAssets.WETH_ORACLE;
    address public constant TO_ORACLE = 0xb031a238940e8051852b156f3efDc462fc34f37B; // rETH

    function run() external broadcast {
        AaveSwapper(SWAPPER_INSTANCE).cancelSwap(
            TRADE_MILKMAN,
            PRICE_CHECKER,
            FROM_TOKEN,
            TO_TOKEN,
            FROM_ORACLE,
            TO_ORACLE,
            msg.sender,
            AMOUNT,
            SLIPPAGE
        );
    }
}
