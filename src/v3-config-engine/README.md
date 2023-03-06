## Aave v3 config engine

![Alt text](/resources/configs-engine.svg)

## What is the AaveV3ConfigEngine?

The `AaveV3ConfigEngine` is a helper smart contract to abstract good practices when doing "admin" interactions with the Aave v3 protocol, but built on top, without touching the core contracts.

At the same time, it defines a new interface oriented to simplify developer experience when coding proposal payloads: the `AaveV3ConfigEngine` is built from our experience supervising governance payloads review, for actions like full cycle of listing assets, modify caps (supply/borrow), changing collateral or borrow related parameters and changing the price feeds of assets.

## How to use the engine?

The engine is not designed to be used directly when writing a payload, but through abstract contracts that we will call `Base Aave v3 Payloads`.

This repository contains `Base Aave v3 Payloads` for all the Aave v3 instances, under the hood powered by the engine and aave-address-book, and abstracting all the complexity: ordering of execution of actions, extra validations, deciding when to keep a current configured parameter and how to get it, etc.

As base for any payload, you only need to inherit from the corresponding (per pool) `Base Aave v3 Payload`, for example inheriting from `AaveV3PayloadEthereum` in the case of Ethereum, `AaveV3PayloadAvalanche` in the case of Avalanche, and so on.

If you want just to do one or multiple listings, you only need to define the listing within a `newListings()` function, and the base payload will take care of executing it correctly for you.

Do you want instead to update supply/borrow caps? Same approach as with the listings, you only need to define the update of caps within a `capsUpdates()` function, and the base payload will take care of the rest.

Do you want to update the price-feed of an asset? You only need to define the update of price feed within a `updatePriceFeeds()` function, and the base payload will take care of the rest.

Change collateral-related parameters? Same approach as previous, you only need to define the update within a `updateCollateralSide()` function, and the base payload will take care of the rest.

Change Borrow-related parameters? Same as previous, just define the update within a `updateBorrowSide()` function, and the base payload will take care of the rest.

### Internal aspects to consider

- Frequently, at the same time that you want to do an update of parameters or listing, you also want to do something extra before or after (e.g. create an eMode category that you will use for the new asset to be listed).
The `Base Aave v3 Payload` defines `_preExecute()` and `_postExecute()` hook functions, that you can redefine on your payload and will the execute before and after all configs changes/listings you define.

- The payload also allow you to group changes of parameters and listings, just by defining at the same time the aforementioned `newListings()`, `capsUpdate()` and/or `updateCollateralSide()`. For reference, the execution ordering is the following:
  1. `_preExecute()`
  2. `newListingsCustom()`
  3. `newListings()`
  4. `capsUpdates()`
  5. `priceFeedsUpdates()`
  6. `borrowsUpdates()`
  7. `collateralsUpdates()`
  8. `_postExecute()`

## Links to examples
- [Simple mock listing on Aave v3 Polygon](../test/mocks/AaveV3PolygonMockListing.sol)
- [Simple custom mock listing on Aave V3 Ethereum with custom token impl](../test/mocks/AaveV3EthereumMockCustomListing.sol)
- [Mock caps updates (only supply, keeping current borrow cap) on Aave v3 Ethereum](../test/mocks/AaveV3EthereumMockCapUpdate.sol)
- [Mock collateral updates (changing some, keeping current values on others), on Aave v3 Avalanche](../test/mocks/AaveV3AvalancheCollateralUpdate.sol)
- [Mock borrow updates (changing some, keeping current values on others), on Aave v3 Polygon](../test/mocks/AaveV3PolygonBorrowUpdate.sol)
- [Mock rates updates (changing some, keeping current values on others), on Aave v3 Optimism](../test/mocks/AaveV3OptimismMockRatesUpdate.sol)
- [Mock price feed updates on Aave v3 Polygon](../test/mocks/AaveV3PolygonPriceFeedUpdate.sol)
