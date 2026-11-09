# Native MT5 Deal Attribution and Slippage Evidence

## Purpose

The Strategy Tester deal export supports position-level strategy/regime analysis and explicit execution-cost coverage. This is research telemetry only. It does not change order admission, sizing, stops, targets, or live execution.

## Attribution lineage

- Each opening deal reads the originating order comment and parses the EA decision identity (MT#decision:Lleg).
- The active outcome tracker supplies the selected strategy and market regime for that decision.
- The exporter stores that identity against the stable MT5 DEAL_POSITION_ID.
- Partial exits and later deal rows inherit the original position attribution from that stable identifier.
- Conflicting labels for one position are marked CONFLICT; missing lineage is UNTAGGED. Neither is silently guessed.
- The native CSV carries decision_id, strategy, and regime on every deal row. The Python ledger verifies that a completed position has consistent labels before grouping it.

## Slippage measurement

- The reference is the historical order's ORDER_PRICE_OPEN, not a bar close or a later quote.
- Slippage is calculated only when the historical order is a market ORDER_TYPE_BUY or ORDER_TYPE_SELL, the deal direction matches, and the reference price and point size are valid.
- Signed points are adverse-positive and favorable-negative: BUY uses (fill - requested) / point; SELL uses (requested - fill) / point.
- Adverse cash cost is calculated with OrderCalcProfit from requested price to actual fill and floored at zero. For closing deals, the calculation uses the opposite hypothetical position direction so an adverse close fill has the correct cost sign. Favorable execution is retained as negative points and zero adverse cash cost.
- Pending stop/limit orders are not scored by this field. Their trigger gaps and limit-price improvement are different execution phenomena; this export leaves them unknown rather than mislabelling them as market slippage.
- If requested price, direction, or cash conversion is unavailable, the CSV writes blank numeric slippage fields and slippage_known=false. The ledger never converts missing evidence into zero.

## Position-level metrics

- A position's slippage cost is complete only if every deal row for that position has known slippage.
- Incomplete positions retain slippage_cost_cash=null; the report separately shows known/unknown counts and coverage.
- The report includes decision, strategy, and regime attribution coverage, so missing lineage cannot masquerade as a fully attributed sample.
- Commission, swap, fees, and realized profit remain separately exported and netted by the existing position-ledger rules.

## Validation limits

This establishes the export's data contract and arithmetic, not that Strategy Tester order-price semantics replicate live broker execution. Verify requested-price semantics on representative market orders in MT5 Strategy Tester and compare against broker demo fills before using these figures to promote an exit or strategy configuration.
