# Fibonacci Progression / Martingale Lab — Research Only

This is a risk study, not a deployment recommendation. A Fibonacci
progression after losses remains a martingale family. The outcomes are
the current 4-year P0 normalized R sequence; no claim is made that a
different lot size preserves exact live R after broker rounding.

Sequence length: 109 realized outcomes. Drawdown limit: 15.0%.

## Historical sequence

| Base risk | Multiplier cap | Final | ROI | Max DD | Trades | Max risk |
|---:|---:|---:|---:|---:|---:|---:|
| 0.50% | none | $3234 | 29.4% | 3.0% | 109 | 2.5% |
| 0.50% | 3 | $3196 | 27.8% | 3.0% | 109 | 1.5% |
| 0.50% | 5 | $3234 | 29.4% | 3.0% | 109 | 2.5% |
| 1.00% | none | $4149 | 66.0% | 5.9% | 109 | 5.0% |
| 1.00% | 3 | $4053 | 62.1% | 5.9% | 109 | 3.0% |
| 1.00% | 5 | $4149 | 66.0% | 5.9% | 109 | 5.0% |
| 2.00% | none | $6670 | 166.8% | 11.6% | 109 | 10.0% |
| 2.00% | 3 | $6378 | 155.1% | 11.6% | 109 | 6.0% |
| 2.00% | 5 | $6670 | 166.8% | 11.6% | 109 | 10.0% |

## Shuffled path stress

The historical trade outcomes are randomly reordered 10,000 times.
This is not a full block bootstrap, but it demonstrates how much the
martingale result depends on the lucky order of wins and losses.

| Base risk | Cap | Paths >15% DD | Median DD | 95th DD | 99th DD | Median final |
|---:|---:|---:|---:|---:|---:|---:|
| 0.50% | none | 4.1% | 3.6% | 12.0% | 21.0% | $3255 |
| 0.50% | 3 | 0.0% | 3.7% | 7.6% | 9.5% | $3213 |
| 0.50% | 5 | 0.3% | 3.6% | 9.6% | 12.8% | $3241 |
| 1.00% | none | 14.5% | 7.2% | 23.1% | 38.4% | $4198 |
| 1.00% | 3 | 4.0% | 7.3% | 14.7% | 18.2% | $4097 |
| 1.00% | 5 | 13.3% | 7.2% | 18.5% | 24.2% | $4166 |
| 2.00% | none | 43.2% | 14.0% | 42.2% | 64.1% | $6807 |
| 2.00% | 3 | 44.5% | 14.2% | 27.7% | 33.6% | $6505 |
| 2.00% | 5 | 43.2% | 14.0% | 34.2% | 43.2% | $6715 |
| 3.00% | none | 80.0% | 20.6% | 57.3% | 80.7% | $10680 |
| 3.00% | 3 | 80.1% | 20.8% | 39.1% | 46.6% | $10035 |
| 3.00% | 5 | 80.0% | 20.6% | 47.6% | 58.2% | $10504 |

## Verdict

The progression can make a favorable historical path look better, but
it does not create edge. A loss cluster increases the next position
exactly when the strategy is not working. Any cap or loss-stop that
prevents ruin also removes the recovery property, leaving a more complex
risk schedule with no demonstrated expectancy advantage.

