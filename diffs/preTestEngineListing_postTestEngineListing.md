## Reserve changes

### Reserves added

#### 1INCH ([0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f](https://polygonscan.com/address/0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f))

| description | value |
| --- | --- |
| decimals | 18 |
| isActive | true |
| isFrozen | false |
| supplyCap | 85,000 1INCH |
| borrowCap | 60,000 1INCH |
| debtCeiling | 0 $ |
| isSiloed | false |
| isFlashloanable | false |
| eModeCategory | 1 |
| oracle | [0x443C5116CdF663Eb387e72C688D276e702135C87](https://polygonscan.com/address/0x443C5116CdF663Eb387e72C688D276e702135C87) |
| oracleDecimals | 8 |
| oracleDescription | 1INCH / USD |
| oracleLatestAnswer | 0.36313594 |
| usageAsCollateralEnabled | true |
| ltv | 82.5 % |
| liquidationThreshold | 86 % |
| liquidationBonus | 5 % |
| liquidationProtocolFee | 10 % |
| reserveFactor | 10 % |
| aToken | [0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD](https://polygonscan.com/address/0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD) |
| aTokenImpl | [0xCf85FF1c37c594a10195F7A9Ab85CBb0a03f69dE](https://polygonscan.com/address/0xCf85FF1c37c594a10195F7A9Ab85CBb0a03f69dE) |
| variableDebtToken | [0xE701126012EC0290822eEA17B794454d1AF8b030](https://polygonscan.com/address/0xE701126012EC0290822eEA17B794454d1AF8b030) |
| variableDebtTokenImpl | [0x79b5e91037AE441dE0d9e6fd3Fd85b96B83d4E93](https://polygonscan.com/address/0x79b5e91037AE441dE0d9e6fd3Fd85b96B83d4E93) |
| stableDebtToken | [0xc889e9f8370D14A428a9857205d99BFdB400b757](https://polygonscan.com/address/0xc889e9f8370D14A428a9857205d99BFdB400b757) |
| stableDebtTokenImpl | [0xF4294973B7E6F6C411dD8A388592E7c7D32F2486](https://polygonscan.com/address/0xF4294973B7E6F6C411dD8A388592E7c7D32F2486) |
| borrowingEnabled | true |
| stableBorrowRateEnabled | false |
| isBorrowableInIsolation | false |
| interestRateStrategy | [0x03733F4E008d36f2e37F0080fF1c8DF756622E6F](https://polygonscan.com/address/0x03733F4E008d36f2e37F0080fF1c8DF756622E6F) |
| liquidityIndex | 1 |
| variableBorrowIndex | 1 |
| aTokenName | Aave Polygon 1INCH |
| aTokenSymbol | aPol1INCH |
| currentLiquidityRate | 0 % |
| currentVariableBorrowRate | 0 % |
| isPaused | false |
| stableDebtTokenName | Aave Polygon Stable Debt 1INCH |
| stableDebtTokenSymbol | stableDebtPol1INCH |
| variableDebtTokenName | Aave Polygon Variable Debt 1INCH |
| variableDebtTokenSymbol | variableDebtPol1INCH |
| optimalUsageRatio | 45 % |
| maxExcessStableToTotalDebtRatio | 80 % |
| maxExcessUsageRatio | 55 % |
| optimalStableToTotalDebtRatio | 20 % |
| baseVariableBorrowRate | 0 % |
| variableRateSlope1 | 7 % |
| variableRateSlope2 | 300 % |
| baseStableBorrowRate | 9 % |
| stableRateSlope1 | 0 % |
| stableRateSlope2 | 0 % |
| interestRate | ![ir](/.assets/4ab0dbcff3f330539d66319942d38435e45137bf.svg) |
| eMode.label | Stablecoins |
| eMode.ltv | 93 % |
| eMode.liquidationThreshold | 95 % |
| eMode.liquidationBonus | 1 % |
| eMode.priceSource | 0x0000000000000000000000000000000000000000 |


## Raw diff

```json
{
  "reserves": {
    "0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f": {
      "from": null,
      "to": {
        "aToken": "0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD",
        "aTokenImpl": "0xCf85FF1c37c594a10195F7A9Ab85CBb0a03f69dE",
        "aTokenName": "Aave Polygon 1INCH",
        "aTokenSymbol": "aPol1INCH",
        "borrowCap": 60000,
        "borrowingEnabled": true,
        "currentLiquidityRate": 0,
        "currentVariableBorrowRate": 0,
        "debtCeiling": 0,
        "decimals": 18,
        "eModeCategory": 1,
        "interestRateStrategy": "0x03733F4E008d36f2e37F0080fF1c8DF756622E6F",
        "isActive": true,
        "isBorrowableInIsolation": false,
        "isFlashloanable": false,
        "isFrozen": false,
        "isPaused": false,
        "isSiloed": false,
        "liquidationBonus": 10500,
        "liquidationProtocolFee": 1000,
        "liquidationThreshold": 8600,
        "liquidityIndex": "1000000000000000000000000000",
        "ltv": 8250,
        "oracle": "0x443C5116CdF663Eb387e72C688D276e702135C87",
        "oracleDecimals": 8,
        "oracleDescription": "1INCH / USD",
        "oracleLatestAnswer": 36313594,
        "reserveFactor": 1000,
        "stableBorrowRateEnabled": false,
        "stableDebtToken": "0xc889e9f8370D14A428a9857205d99BFdB400b757",
        "stableDebtTokenImpl": "0xF4294973B7E6F6C411dD8A388592E7c7D32F2486",
        "stableDebtTokenName": "Aave Polygon Stable Debt 1INCH",
        "stableDebtTokenSymbol": "stableDebtPol1INCH",
        "supplyCap": 85000,
        "symbol": "1INCH",
        "underlying": "0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f",
        "usageAsCollateralEnabled": true,
        "variableBorrowIndex": "1000000000000000000000000000",
        "variableDebtToken": "0xE701126012EC0290822eEA17B794454d1AF8b030",
        "variableDebtTokenImpl": "0x79b5e91037AE441dE0d9e6fd3Fd85b96B83d4E93",
        "variableDebtTokenName": "Aave Polygon Variable Debt 1INCH",
        "variableDebtTokenSymbol": "variableDebtPol1INCH"
      }
    }
  },
  "strategies": {
    "0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f": {
      "from": null,
      "to": {
        "address": "0x03733F4E008d36f2e37F0080fF1c8DF756622E6F",
        "baseStableBorrowRate": "90000000000000000000000000",
        "baseVariableBorrowRate": 0,
        "maxExcessStableToTotalDebtRatio": "800000000000000000000000000",
        "maxExcessUsageRatio": "550000000000000000000000000",
        "optimalStableToTotalDebtRatio": "200000000000000000000000000",
        "optimalUsageRatio": "450000000000000000000000000",
        "stableRateSlope1": 0,
        "stableRateSlope2": 0,
        "variableRateSlope1": "70000000000000000000000000",
        "variableRateSlope2": "3000000000000000000000000000"
      }
    }
  }
}
```