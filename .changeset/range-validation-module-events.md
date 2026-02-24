---
'@aave-dao/aave-helpers-js': patch
---

Add IRangeValidationModule events (DefaultRangeConfigSet, MarketRangeConfigSet) to eventDb so that RANGE_VALIDATION_MODULE contract events are decoded in diff reports instead of showing raw topics. Also fixes a bug where formatValue crashed on decoded struct args containing BigInt values.
