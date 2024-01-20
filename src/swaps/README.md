# Aave <> CoW Swap: AaveSwapper

The AaveSwapper is a smart contract tool developed in order to more easily allow the Aave DAO to swap its tokens.
Up until now, the DAO relied on custom one-use contracts in order to accomplish the swap of one token for another.
Some examples include the BAL <> AAVE swap from 2022, the acquisition of CRV or the acquisition of B-80BAL-20WETH.
All the instances listed above required significant time to develop, test, and review, all while reinventing the
wheel every time for something that should be easy to reuse.

AaveSwapper facilitates swaps of tokens by the DAO without the constant need to review the contracts that do so.

## How It Works

AaveSwapper relies on [Milkman](https://github.com/charlesndalton/milkman), a smart contract that builds on top of
[COW Swap](https://swap.cow.fi/#/faq/protocol), under the hood in order to find the best possible swap execution for
the DAO while protecting funds from MEV exploits and bad slippage.

AaveSwapper is a permissioned smart contract, and it has two potential privileged users: the owner and the guardian.
The owner will be the DAO (however, ownership can be transferred) and the guardian is an address to be chosen by the
DAO to more easily cancel swaps without relying on governance. AaveSwapper can hold funds and swap for other tokens
and keep them in case the DAO chooses so. AaveSwapper can only withdraw tokens to the Collector contract.

### Methods

```
function swap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
  ) external onlyOwnerOrGuardian
```

Swaps `fromToken` to `toToken` in the specified `amount`. The recipient of the `toToken` and sends the acquired funds to the recipient.

Slippage is specified in basis points, for example `100` is 1% slippage. The maximum amount would be `10_000` for 100% slippage.

A note on slippage and CoW Swap:

Slippage not only accounts for the difference in price, but also gas costs incurred for the swap itself. What follows is an example:
A user wants to swap 100 USDC for DAI, the price is about 1-to-1 as they are both stablecoins. The slippage needed for this trade, with
gas prices of 80 gwei could be over 20%, because the transaction itself might cost around $20 dollars, and then the solver needs an incentive
to do the trade so maybe the actual slippage in price is 1% and it trades at 1.005 cost of DAI per USDC.

For a 1,000,000 USDC to DAI swap, this looks very different. Slippage might be around 0.005% where the solver gets $30, plus gas costs of
around $20 dollars, so setting the slippage to 0.5% or 1% to ensure that the swap is picked up is more than enough. The slippage tolerance
does not mean that's what the trade will definitely trade at. CoW Swap finds the best match and then executes at that price. Solvers are
competing at market prices for swaps all the time and they are incentivized to keep prices tight in order to get picked as executors.

Some tokens that are not "standard" ERC-20, such as Aave Interest Bearing Tokens (aTokens) are more gas consuming because the solvers
take into account the costs of wrapping and unwrapping the tokens. AaveSwapper supports aToken to aToken swaps though it is easier to
swap between underlyings.

Depending on the tokens and amounts, slippage will have to vary. A good heuristic is:

Trades of $1,000,000 worth of value or more, around 0.5-1% slippage.
Trades in the six figures, 1-2%.
Trades in the high five-figures, around 3%.
Trades below $15,000 worth of value, 5% slippage.
Trades in the low thousands and less are not really worth swapping because gas costs are a huge proportion of the swap.

The [CoW Swap UI](https://swap.cow.fi/#/1/swap/WETH) can be checked to get an estimate of slippage if executing at that time.

AaveSwapper uses Chainlink oracles for its slippage protection feature. Governance should enforce that all oracles set are
base-USD (ie: V3 oracles and not V2 oracles). AaveSwapper supports base-ETH swaps as well, but both bases have to be the same.
For example USDC/ETH to AAVE/ETH or USDC/USD to AAVE/USD. It does not support USDC/ETH to AAVE/USD swaps and this can lead to
bad trades because of price differences.

```
function limitSwap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwner
```

Limit orders are used when wanting a specific price and not minding leaving an order open. When dealing with DAO swaps, knowing the price 5 days in advance is hard, and maybe relying on oracles is not what the DAO wants, especially dealing with low-liquidty tokens, or big orders that might move the market a lot but not the Oracle reference price.

The `amountOut` here is in the token that is to be RECEIVED. For example, let's say we want to swap 1 wETH for USDC, and the price is $2,000, and we want to get that or better, we would specify the swap in terms of the USDC to be received, in this case, 2,000 USDC. The `amountOut` is measured in the smallest atom of the currency. For tokens with 18 decimals, this would be quotedin wei. For 6 decimals, it would be in 0.000001 increments.

For example, if swapping 1 wETH for DAI, at a price of 2,000, then the `amountOut` needs to be `2000000000000000000000`. If swapping 1 wETH for USDC, the `amountOut` needs to be `2000000000` instead.

Swap fees/gas costs need to be taken into account, especially for smaller orders. For orders in the hundreds of thousands, or millions, this is just going to be a very tiny amount in percentage terms so it won't really matter much, but for a small order, it might. Take for example, the 1 wETH for USDC swap described above. If the limit order is at 2,000 and gas costs are $50, the trade will not settle until price trades at 2,050 because that needs to be taken from the value of the swap. Alternatively, the limit could be made 1,950 because the DAO wants the trade to settle once it hits 2,000 and not have to worry about it.

Limit orders are best suited for stable-to-stable swaps, especially bigger orders as the gas costs are going to be a tiny franction and swaps are likely to occurr rather easily.

```
 function twapSwap(
    address handler,
    address relayer,
    address fromToken,
    address toToken,
    address recipient,
    uint256 sellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external onlyOwner {
```

TWAP (or time-weighted average price) orders are used when wanting to average a certain price for a swap. For example, let's say the DAO wants to acquire TokenX but the DAO wants to do periodical purchases in order to get an average price and not worry about fluctuations. With TWAP orders, the DAO could for example purchase a certain amount of TokenX every Monday, every hour, or every first of the month.

The `handler` is the address of the COW Swap contract that can take TWAP orders, the address can be found [here](https://github.com/cowprotocol/composable-cow?tab=readme-ov-file#deployed-contracts) under TWAP. The `relayer` address is the COW Swap contract that handles moving of tokens, more can be read [here](https://docs.cow.fi/cow-protocol/reference/contracts/core/vault-relayer).

`fromToken` is the token the user wants to sell, and `toToken` is the token that is to be acquired. `recipient` is the address that will receive the tokens, which is likely to be the Aave V3 Ethereum Collector.

For the TWAP specific orders, the parameters and their explanation are as follows:

`sellAmount` is the amount of tokens of `fromToken` to be sold each time. For example, let's say the DAO wants to sell 100,000 units of DAI every week for one month, then `sellAmount` would be 25,000, as there will be 4 swaps total.

`minPartLimit` is the minimum amount the DAO is willing to accept per order. For example, following the above example, and with WETH trading at 2,000, which would yield 50 WETH (or 12.5 per each of the four orders), the minimum the DAO is willing to take is 12 (or 10, or anything).

`startTime` is when the orders can first take effect, in unix epoch seconds. For example, the DAO wants the orders to take place on Mondays, and the proposal is to be executed on a Sunday, one can specify the `startTime` as block.timestamp + 1 day to ensure it's on Monday.

`numParts` is the number of swaps to take place. In the example referenced above, this would be 4, to do a weekly swap for a month.

`partDuration` is how long to wait until the next order. Again, using the example above, this would be the uint256 representation of 1 week. If the DAO wanted daily buys, this would be 1 day in uint256.

`span` is to allow some extra customization on time of day, or days of the week the swaps will take place. Using the daily purchases example, the day has 86400 seconds, if the DAO only wanted to swap during the first half of the day, `span` would be set to 43200. The value 0 means the order can take place anytime during the interval (anytime during the day, week, month, etc).

```
function cancelSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
) external onlyOwnerOrGuardian
```

This methods cancels a pending trade. Trades should take just a couple of minutes to be picked up and traded, so if something's not right, the user
should assume something's off.

Most likely, this function will be called when a swap is not getting executed because slippage might be too tight and there's no match for it.

```
function cancelLimitSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwnerOrGuardian
```

This methods cancels a pending limit trade. Trades should take just a couple of minutes to be picked up and traded, so if something's not right, the user
should think that something might be off.

For limit orders, keep in mind the price might be at the the limit price, but having to account for the cost of the swap might need the price to move a bit further. This should not matter for big swaps but it could be a thing in smaller swaps (especially around test swaps for validation).

```
function cancelTwapSwap(
    address handler,
    address fromToken,
    address toToken,
    address recipient,
    uint256 sellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external onlyOwnerOrGuardian
```

This method cancels a pending TWAP swap. Portions that have already happened will not be reimbursed, but any subsequent ones will be cancelled.

```

  function getExpectedOut(
    address priceChecker,
    uint256 amount,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle
  ) public view returns (uint256)
```

Get the expected amount of tokens when doing a swap. Informational only.

`function emergencyTokenTransfer(address token, address recipient, uint256 amount) external onlyRescueGuardian`

Withdrawal function for funds to leave AaveCurator. Only the owner can call this function.

```
  function _getPriceCheckerAndData(
    address fromToken,
    address toToken,
    uint256 slippage
) internal view returns (address, bytes memory)
```

Read-only function to get an idea of how many tokens to expect when performing a swap. This helper can be used
to determine the slippage percentage to submit on the swap.

### Potential Extensions

This library includes some abstract payloads to be used by developers to more easily swap and then handle the acquired assets.

`function deposit(address token, uint256 amount) external onlyOwnerOrGuardian`

Deposits funds held on AaveCurator into Aave V2/Aave V3 on behalf of the Collector, depending on the payload used.

### Deployed Address

Please check out https://github.com/charlesndalton/milkman for updates on addresses under the DEPLOYMENTS.md section.

Milkman: [`0x11C76AD590ABDFFCD980afEC9ad951B160F02797`](https://etherscan.io/address/0x11C76AD590ABDFFCD980afEC9ad951B160F02797)
Chainlink Price Checker: [`0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c`](https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c)
B80BAL20WETH Price Checker: [`0xBeA6AAC5bDCe0206A9f909d80a467C93A7D6Da7c`](https://etherscan.io/address/0xBeA6AAC5bDCe0206A9f909d80a467C93A7D6Da7c)
Limit Order Price Checker: [`0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802`](https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802)
Mainnet: [`0x3ea64b1C0194524b48F9118462C8E9cd61a243c7`](https://etherscan.io/address/0x3ea64b1C0194524b48F9118462C8E9cd61a243c7)
