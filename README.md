<div align="center">

<img src="assets/nani_banner.jpg" alt="Nani" width="600" />

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,6&height=200&section=header&text=Nani&fontSize=80&fontColor=ffffff&animation=fadeIn&fontAlignY=38&desc=SAR-Directed%20Cluster%20EA%20for%20MetaTrader%205&descAlignY=58&descSize=20" />

![MQL5](https://img.shields.io/badge/MQL5-MetaTrader%205-0b5ed7?style=for-the-badge&logo=metatrader&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-00b894?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Backtested%20%26%20Validated-f39c12?style=for-the-badge)
![Risk](https://img.shields.io/badge/Risk-Trading%20Involves%20Real%20Loss-e74c3c?style=for-the-badge)

</div>

## What Nani is

Nani is a MetaTrader 5 Expert Advisor that merges two independently-designed pieces into one
tested system:

- **Direction signal** — Parabolic SAR with an ATR-volatility-regime filter and a candle-range
  filter, adapted from `QW_SRP_Gold_v17.mq5`. SAR flips frequently (not a rare event), which is
  what makes it a good fit for driving a cluster system without signal starvation.
- **Money management** — a 2-block cluster system adapted from `VolExpCluster_EA.mq5`: block 1
  opens a fixed-size block of market positions in the signalled direction; block 2 pyramids a
  **second** block onto block 1 only if block 1 is already running in profit (never a fresh
  signal). The whole basket closes at a small, fixed percentage of balance; a basket-wide stop
  protects the downside.

The name is simply what this EA is called in the project it came from — it isn't a claim about
performance.

## Backtest validation

Tested against 2 years of XAUUSD H1 price history (2024–2026), split into two independent
1-year halves with **no parameters tuned on the data** (every threshold below is the value the
EA ships with, not something fit to this specific history):

| Period | Baskets | Win rate | Return | Max drawdown |
|---|---|---|---|---|
| First half (Oct 2024 – Oct 2025) | 98 | 92.9% | +1.94% | -2.25% |
| Second half (Oct 2025 – Oct 2026) | 164 | 91.5% | +5.50% | -3.67% |
| Full period | 263 | 91.6% | +7.55% | -3.65% |

Both halves were independently profitable with a consistent win rate — the second half actually
performed *better* than the first, which is a reasonable (not conclusive) sign against
overfitting. This is backtest evidence on historical data, not a live track record, and should
be treated accordingly (see **Risk Disclosure** below).

> **Note on the table above:** those numbers were produced with `InpBasketLossPercent = 1.0`.
> The version in this repo ships with a looser default (`1.5`) so it's a safe, honestly-labeled
> starting point rather than a silent copy of the exact validated config — see
> **Default parameters** below for what changes and by how much. Running the backtest yourself
> against this repo's shipped defaults will not reproduce the table above; it reproduces a
> real, still-profitable, but weaker result (roughly +3.5% vs +7.55% over the same H1 period).

## Default parameters

| Group | Parameter | Default | Meaning |
|---|---|---|---|
| SAR | `InpSARStep` / `InpSARMax` | 0.02 / 0.2 | Standard Parabolic SAR acceleration settings |
| ATR filter | `InpATRPeriod` / lookback | 14 / 50 bars | Only trades when current volatility is 0.5x–2.5x its 50-bar average |
| Candle filter | `InpCandleLB` / mult | 20 / 2.5x | Rejects entries on abnormally large bars (>2.5x the 20-bar average range) |
| Cluster | `InpInitialLot` | 0.01 | Lot size per position in a block |
| Cluster | `InpMaxBlockCount` | 3 | Positions per block (6 total if block 2 fires) |
| Exit | `InpTargetProfitPercent` | 0.07% | Basket closes at this % of account balance |
| Exit | `InpBasketLossPercent` | 1.5% | Basket-wide stop-loss, % of account balance (looser than the validated 1.0% -- see note above) |

## ⚠️ Risk Disclosure

**Trading leveraged instruments such as gold (XAUUSD) carries a high level of risk and can
result in the loss of some or all of your invested capital. Past backtested performance does
not guarantee future results.**

- **No per-trade stop-loss.** This EA's only downside protection is the basket-wide
  `InpBasketLossPercent` stop. Individual positions inside a basket are not independently
  protected. In fast-moving or gapping markets, actual losses on a basket-stop event can exceed
  what a clean historical backtest shows, because backtests assume fills at the modeled stop
  level and do not fully capture slippage, requotes, or gaps.
- **Backtest, not live track record.** The results above come from historical simulation on
  2024–2026 XAUUSD price data. They demonstrate that the strategy held up across two
  independent periods in that specific window — they are not a promise of future performance,
  and market conditions change.
- **Position sizing compounds with account size.** `InpInitialLot` is a fixed lot value by
  default; review and adjust it relative to your own account size and risk tolerance before
  running this live.
- **Test on a demo account first.** Anyone using this EA should validate it on a demo account
  under their own broker's actual spread/execution conditions before committing real capital,
  and should understand every input parameter before changing the defaults.
- This repository and its contents are provided for **educational and research purposes**. They
  do not constitute financial advice. You are solely responsible for any trading decisions and
  outcomes.

## Installation

1. Copy `Nani.mq5` into your MetaTrader 5 `MQL5/Experts/` folder.
2. Compile it in MetaEditor (`F4` or Compile button) — requires no external indicators or
   includes beyond the standard `Trade/Trade.mqh` shipped with MT5.
3. Attach to an XAUUSD chart. The EA was validated on **H1**; other timeframes have not been
   tested and should not be assumed to behave the same way.
4. **A hedging-type trading account is required** — the cluster logic opens multiple independent
   positions in the same direction, which a netting account would merge into one averaged
   position and break the level count.

## License

MIT License — see [LICENSE](LICENSE). Use, modify, and distribute freely, with no warranty of
any kind. See the Risk Disclosure above before using this with real funds.
