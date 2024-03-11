# Aave Arbitrum -> Mainnet ERC20 Bridge

Arbitrum does offer a way to bridge directly from their network to Mainnet using their standard ArbERC20 tokens. There is a 'gateway' address that is used to bridge to mainnet. It can be called from the tokens themselves, however, it requires some domain knowledge. This contract facilitates the bridging of tokens in order to make managing Aave DAO's treasury easier.

The same contract exists on both chains with the same address, so this contract will receive funds from the Arbitrum Collector, then call to bridge the received tokens. After the Arbitrum rollup happens, the "burn proof" will be generated via API. At this point, the mainnet contract can be called. `exit()` will give the mainnet collector contract the tokens that were bridged over from Arbitrum.

In order to generate the proof for an exit, as well as the other required data, please install the `aave-cli` tool which can be found [here](https://github.com/bgd-labs/aave-cli).

In order to generate the proof, run the following command:

`aave-cli arbitrum-bridge-exit [TX_HASH] [INDEX] [ARBITRUM_BLOCK_OF_TX]`

Where the TX_HASH is the hash where the bridge was initiated on Arbitrum, the INDEX is the withdrawal index (ie: if there are 3 tokens bridged in the same transaction, the indexes will be 0, 1 and 2), and ARBITRUM_BLOCK_OF_TX, which is the block the bridge transaction happened at.

## Functions

```
function bridge(
    address token,
    address l1Token,
    address gateway,
    uint256 amount
  ) external;
```

Callable on Arbitrum to withdraw ERC20 token. It withdraws `amount` of passed `token` to mainnet. The gateway address can be found either in the token's read methods where it's called `l1gateway()` or `gateway()`, depending on the token. You can also refer to the Arbitrum [docs](https://docs.arbitrum.io/devs-how-tos/bridge-tokens/how-to-bridge-tokens-standard) and the relevant [addresses](https://docs.arbitrum.io/for-devs/useful-addresses).

```
function exit(
    bytes32[] calldata proof,
    uint256 index,
    address l2sender,
    address to,
    uint256 l2block,
    uint256 l1block,
    uint256 l2timestamp,
    uint256 value,
    bytes calldata data
  ) external
```

Callable on Mainnet to finish the withdrawal process. Callable ~7 days after `bridge()` is called and proof is available via `aave-cli`. Arbitrum currently doesn't support getting this information via API (we have requested this feature).

`function emergencyTokenTransfer(address erc20Token, address to, uint256 amount) external;`

Callable on Arbitrum. Withdraws tokens from bridge contract back to Aave Collector on Arbitrum.

## Burn Proof Generation

After you have called `bridge()` Arbitrum, it will take ~7 days for the withdrawal to be available (it's a rollup solution after all). Once it's available, a user can withdraw on Mainnet.

Here's a sample transaction: https://arbiscan.io/tx/0x726c0b903d77088af36e06dfe6fd40df318ba83b8a93726fa30fab018cb43357

https://arbiscan.io/tx/0x726c0b903d77088af36e06dfe6fd40df318ba83b8a93726fa30fab018cb43357#eventlog

The relevant log in this example is #7, from address `0x0000000000000000000000000000000000000064` which is an Arbitrum pre-compiled contract. Foundry does not currently support pre-compiled contracts in any networks other than Mainnet, so unfortunately a script cannot be used to run test commands. You can use the arbiscan.io UI as an alternative.

The exit transaction is here: https://etherscan.io/tx/0xa34c3725cc95773eedf96b03e9672ad77940b27fc5b1b94441e6587dec014ecd

You can see the input data which was retrieved via the Aave CLI tool.

## Deployed Addresses

Mainnet:
Arbitrum:
