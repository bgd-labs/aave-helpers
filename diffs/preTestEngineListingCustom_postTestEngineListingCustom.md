## Reserve changes

### Reserves added

#### 1INCH ([0x111111111117dC0aa78b770fA6A738034120C302](https://etherscan.io/address/0x111111111117dC0aa78b770fA6A738034120C302))

| description | value |
| --- | --- |
| supplyCap | 85,000 1INCH |
| borrowCap | 60,000 1INCH |
| aToken | [0x7B95Ec873268a6BFC6427e7a28e396Db9D0ebc65](https://etherscan.io/address/0x7B95Ec873268a6BFC6427e7a28e396Db9D0ebc65) |
| aTokenImpl | [0x7EfFD7b47Bfd17e52fB7559d3f924201b9DbfF3d](https://etherscan.io/address/0x7EfFD7b47Bfd17e52fB7559d3f924201b9DbfF3d) |
| borrowingEnabled | true |
| debtCeiling | 0 |
| decimals | 18 |
| eModeCategory | 0 |
| interestRateStrategy | ![[0x24701A6368Ff6D2874d6b8cDadd461552B8A5283](https://etherscan.io/address/0x24701A6368Ff6D2874d6b8cDadd461552B8A5283)](/.assets/1_0x24701A6368Ff6D2874d6b8cDadd461552B8A5283.svg) |
| isActive | true |
| isBorrowableInIsolation | false |
| isFlashloanable | false |
| isFrozen | false |
| isSiloed | false |
| liquidationBonus | 5 % |
| liquidationProtocolFee | 10 % |
| liquidationThreshold | 86 % |
| ltv | 82.5 % |
| oracle | [0x72AFAECF99C9d9C8215fF44C77B94B99C28741e8](https://etherscan.io/address/0x72AFAECF99C9d9C8215fF44C77B94B99C28741e8) |
| oracleLatestAnswer | 328,918,384,865,774 |
| reserveFactor | 10 % |
| stableBorrowRateEnabled | true |
| stableDebtToken | [0x90D9CD005E553111EB8C9c31Abe9706a186b6048](https://etherscan.io/address/0x90D9CD005E553111EB8C9c31Abe9706a186b6048) |
| stableDebtTokenImpl | [0x15C5620dfFaC7c7366EED66C20Ad222DDbB1eD57](https://etherscan.io/address/0x15C5620dfFaC7c7366EED66C20Ad222DDbB1eD57) |
| usageAsCollateralEnabled | true |
| variableDebtToken | [0x1b7D3F4b3c032a5AE656e30eeA4e8E1Ba376068F](https://etherscan.io/address/0x1b7D3F4b3c032a5AE656e30eeA4e8E1Ba376068F) |
| variableDebtTokenImpl | [0xaC725CB59D16C81061BDeA61041a8A5e73DA9EC6](https://etherscan.io/address/0xaC725CB59D16C81061BDeA61041a8A5e73DA9EC6) |


## Raw diff

```json
{
  "reserves": {
    "0x111111111117dC0aa78b770fA6A738034120C302": {
      "from": null,
      "to": {
        "aToken": "0x7B95Ec873268a6BFC6427e7a28e396Db9D0ebc65",
        "aTokenImpl": "0x7EfFD7b47Bfd17e52fB7559d3f924201b9DbfF3d",
        "borrowCap": 60000,
        "borrowingEnabled": true,
        "debtCeiling": 0,
        "decimals": 18,
        "eModeCategory": 0,
        "interestRateStrategy": "0x24701A6368Ff6D2874d6b8cDadd461552B8A5283",
        "isActive": true,
        "isBorrowableInIsolation": false,
        "isFlashloanable": false,
        "isFrozen": false,
        "isSiloed": false,
        "liquidationBonus": 10500,
        "liquidationProtocolFee": 1000,
        "liquidationThreshold": 8600,
        "ltv": 8250,
        "oracle": "0x72AFAECF99C9d9C8215fF44C77B94B99C28741e8",
        "oracleLatestAnswer": 328918384865774,
        "reserveFactor": 1000,
        "stableBorrowRateEnabled": true,
        "stableDebtToken": "0x90D9CD005E553111EB8C9c31Abe9706a186b6048",
        "stableDebtTokenImpl": "0x15C5620dfFaC7c7366EED66C20Ad222DDbB1eD57",
        "supplyCap": 85000,
        "symbol": "1INCH",
        "underlying": "0x111111111117dC0aa78b770fA6A738034120C302",
        "usageAsCollateralEnabled": true,
        "variableDebtToken": "0x1b7D3F4b3c032a5AE656e30eeA4e8E1Ba376068F",
        "variableDebtTokenImpl": "0xaC725CB59D16C81061BDeA61041a8A5e73DA9EC6"
      }
    }
  }
}
```