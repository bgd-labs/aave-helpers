## Reserves

### Reserve altered

| key | value |
| --- | --- |
| reserveFactor | ~~2000~~3500 |


| key | value |
| --- | --- |
| interestRateStrategy | ~~0x03733F4E008d36f2e37F0080fF1c8DF756622E6F~~0x27eFE5db315b71753b2a38ED3d5dd7E9362ba93F |
| reserveFactor | ~~1000~~1500 |


| key | value |
| --- | --- |
| reserveFactor | ~~2000~~3500 |


| key | value |
| --- | --- |
| interestRateStrategy | ~~0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4~~0xA9F3C3caE095527061e6d270DBE163693e6fda9D |
| reserveFactor | ~~1000~~2000 |


| key | value |
| --- | --- |
| interestRateStrategy | ~~0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4~~0xA9F3C3caE095527061e6d270DBE163693e6fda9D |


| key | value |
| --- | --- |
| interestRateStrategy | ~~0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4~~0xA9F3C3caE095527061e6d270DBE163693e6fda9D |


| key | value |
| --- | --- |
| interestRateStrategy | ~~0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4~~0xA9F3C3caE095527061e6d270DBE163693e6fda9D |


### Raw diff

```json
{
  "reserves": {
    "0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7": {
      "reserveFactor": {
        "from": 2000,
        "to": 3500
      }
    },
    "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619": {
      "interestRateStrategy": {
        "from": "0x03733F4E008d36f2e37F0080fF1c8DF756622E6F",
        "to": "0x27eFE5db315b71753b2a38ED3d5dd7E9362ba93F"
      },
      "reserveFactor": {
        "from": 1000,
        "to": 1500
      }
    },
    "0x85955046DF4668e1DD369D2DE9f3AEB98DD2A369": {
      "reserveFactor": {
        "from": 2000,
        "to": 3500
      }
    },
    "0xE0B52e49357Fd4DAf2c15e02058DCE6BC0057db4": {
      "interestRateStrategy": {
        "from": "0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4",
        "to": "0xA9F3C3caE095527061e6d270DBE163693e6fda9D"
      }
    },
    "0xE111178A87A3BFf0c8d18DECBa5798827539Ae99": {
      "interestRateStrategy": {
        "from": "0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4",
        "to": "0xA9F3C3caE095527061e6d270DBE163693e6fda9D"
      }
    },
    "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1": {
      "interestRateStrategy": {
        "from": "0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4",
        "to": "0xA9F3C3caE095527061e6d270DBE163693e6fda9D"
      },
      "reserveFactor": {
        "from": 1000,
        "to": 2000
      }
    },
    "0xc2132D05D31c914a87C6611C10748AEb04B58e8F": {
      "interestRateStrategy": {
        "from": "0x41B66b4b6b4c9dab039d96528D1b88f7BAF8C5A4",
        "to": "0xA9F3C3caE095527061e6d270DBE163693e6fda9D"
      }
    }
  },
  "strategies": {
    "0x27eFE5db315b71753b2a38ED3d5dd7E9362ba93F": {
      "from": null,
      "to": {
        "address": "0x27eFE5db315b71753b2a38ED3d5dd7E9362ba93F",
        "baseStableBorrowRate": "68000000000000000000000000",
        "baseVariableBorrowRate": "10000000000000000000000000",
        "maxExcessStableToTotalDebtRatio": "800000000000000000000000000",
        "maxExcessUsageRatio": "200000000000000000000000000",
        "optimalStableToTotalDebtRatio": "200000000000000000000000000",
        "optimalUsageRatio": "800000000000000000000000000",
        "stableRateSlope1": "40000000000000000000000000",
        "stableRateSlope2": "800000000000000000000000000",
        "variableRateSlope1": "38000000000000000000000000",
        "variableRateSlope2": "800000000000000000000000000"
      }
    }
  }
}
```