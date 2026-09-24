# Smart Fibonacci Lab — Research Only

All schedules are capped loss-streak multipliers. The daily stop is
4.0%, the drawdown ceiling is 15.0%,
and the optional high-water guard halves risk after 5.0% DD.
The input is the current normalized net-R P0 sequence; this is not an
exact live-lot validation at every risk fraction.

## Gate

| Policy | Trades | ROI | CAGR | DD | PF-like result | Final |
|---|---:|---:|---:|---:|---:|---:|
| fib_cap3/instrument/1.50% | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap3/instrument/1.50%+ddguard | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap5/instrument/1.50% | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap5/instrument/1.50%+ddguard | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap8/instrument/1.50% | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap8/instrument/1.50%+ddguard | 72 | 89.8% | 27.3% | 3.2% | max-risk 4.5% | $4744.08 |
| fib_cap2/account/1.50% | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap2/account/1.50%+ddguard | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap3/account/1.50% | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap3/account/1.50%+ddguard | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap5/account/1.50% | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap5/account/1.50%+ddguard | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap8/account/1.50% | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap8/account/1.50%+ddguard | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| linear_cap3/account/1.50% | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| linear_cap3/account/1.50%+ddguard | 72 | 85.6% | 26.3% | 3.0% | max-risk 3.0% | $4638.87 |
| fib_cap2/instrument/1.50% | 72 | 85.1% | 26.2% | 3.2% | max-risk 3.0% | $4627.55 |
| fib_cap2/instrument/1.50%+ddguard | 72 | 85.1% | 26.2% | 3.2% | max-risk 3.0% | $4627.55 |
| linear_cap3/instrument/1.50% | 72 | 85.1% | 26.2% | 3.2% | max-risk 3.0% | $4627.55 |
| linear_cap3/instrument/1.50%+ddguard | 72 | 85.1% | 26.2% | 3.2% | max-risk 3.0% | $4627.55 |
| fib_cap2/leg/1.50% | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap2/leg/1.50%+ddguard | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap3/leg/1.50% | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap3/leg/1.50%+ddguard | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap5/leg/1.50% | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap5/leg/1.50%+ddguard | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap8/leg/1.50% | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| fib_cap8/leg/1.50%+ddguard | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| linear_cap3/leg/1.50% | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| linear_cap3/leg/1.50%+ddguard | 72 | 80.7% | 25.0% | 3.0% | max-risk 3.0% | $4518.46 |
| soft_fib3/instrument/1.50% | 72 | 77.3% | 24.1% | 3.2% | max-risk 3.0% | $4431.99 |
| soft_fib3/instrument/1.50%+ddguard | 72 | 77.3% | 24.1% | 3.2% | max-risk 3.0% | $4431.99 |
| soft_fib5/instrument/1.50% | 72 | 77.3% | 24.1% | 3.2% | max-risk 3.0% | $4431.99 |
| soft_fib5/instrument/1.50%+ddguard | 72 | 77.3% | 24.1% | 3.2% | max-risk 3.0% | $4431.99 |
| fixed/account/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fixed/account/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fixed/instrument/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fixed/instrument/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fixed/leg/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fixed/leg/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib3/account/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib3/account/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib3/leg/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib3/leg/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib5/account/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib5/account/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib5/leg/1.50% | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| soft_fib5/leg/1.50%+ddguard | 72 | 72.8% | 22.9% | 3.2% | max-risk 1.5% | $4320.38 |
| fib_cap3/instrument/1.00% | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap3/instrument/1.00%+ddguard | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap5/instrument/1.00% | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap5/instrument/1.00%+ddguard | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap8/instrument/1.00% | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap8/instrument/1.00%+ddguard | 72 | 54.2% | 17.7% | 2.1% | max-risk 3.0% | $3854.43 |
| fib_cap2/account/1.00% | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap2/account/1.00%+ddguard | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap3/account/1.00% | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap3/account/1.00%+ddguard | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap5/account/1.00% | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap5/account/1.00%+ddguard | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap8/account/1.00% | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap8/account/1.00%+ddguard | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| linear_cap3/account/1.00% | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| linear_cap3/account/1.00%+ddguard | 72 | 51.8% | 17.1% | 2.0% | max-risk 2.0% | $3794.91 |
| fib_cap2/instrument/1.00% | 72 | 51.6% | 17.0% | 2.1% | max-risk 2.0% | $3789.72 |
| fib_cap2/instrument/1.00%+ddguard | 72 | 51.6% | 17.0% | 2.1% | max-risk 2.0% | $3789.72 |
| linear_cap3/instrument/1.00% | 72 | 51.6% | 17.0% | 2.1% | max-risk 2.0% | $3789.72 |
| linear_cap3/instrument/1.00%+ddguard | 72 | 51.6% | 17.0% | 2.1% | max-risk 2.0% | $3789.72 |
| fib_cap2/leg/1.00% | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap2/leg/1.00%+ddguard | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap3/leg/1.00% | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap3/leg/1.00%+ddguard | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap5/leg/1.00% | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap5/leg/1.00%+ddguard | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap8/leg/1.00% | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| fib_cap8/leg/1.00%+ddguard | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| linear_cap3/leg/1.00% | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| linear_cap3/leg/1.00%+ddguard | 72 | 49.1% | 16.3% | 2.0% | max-risk 2.0% | $3728.26 |
| soft_fib3/instrument/1.00% | 72 | 47.2% | 15.7% | 2.1% | max-risk 2.0% | $3680.46 |
| soft_fib3/instrument/1.00%+ddguard | 72 | 47.2% | 15.7% | 2.1% | max-risk 2.0% | $3680.46 |
| soft_fib5/instrument/1.00% | 72 | 47.2% | 15.7% | 2.1% | max-risk 2.0% | $3680.46 |
| soft_fib5/instrument/1.00%+ddguard | 72 | 47.2% | 15.7% | 2.1% | max-risk 2.0% | $3680.46 |
| fixed/account/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fixed/account/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fixed/instrument/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fixed/instrument/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fixed/leg/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fixed/leg/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib3/account/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib3/account/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib3/leg/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib3/leg/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib5/account/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib5/account/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib5/leg/1.00% | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| soft_fib5/leg/1.00%+ddguard | 72 | 44.7% | 15.0% | 2.1% | max-risk 1.0% | $3617.62 |
| fib_cap3/instrument/0.50% | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap3/instrument/0.50%+ddguard | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap5/instrument/0.50% | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap5/instrument/0.50%+ddguard | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap8/instrument/0.50% | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap8/instrument/0.50%+ddguard | 72 | 24.5% | 8.6% | 1.1% | max-risk 1.5% | $3113.63 |
| fib_cap2/account/0.50% | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap2/account/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap3/account/0.50% | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap3/account/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap5/account/0.50% | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap5/account/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap8/account/0.50% | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap8/account/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| linear_cap3/account/0.50% | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| linear_cap3/account/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.0% | max-risk 1.0% | $3088.52 |
| fib_cap2/instrument/0.50% | 72 | 23.5% | 8.3% | 1.1% | max-risk 1.0% | $3086.82 |
| fib_cap2/instrument/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.1% | max-risk 1.0% | $3086.82 |
| linear_cap3/instrument/0.50% | 72 | 23.5% | 8.3% | 1.1% | max-risk 1.0% | $3086.82 |
| linear_cap3/instrument/0.50%+ddguard | 72 | 23.5% | 8.3% | 1.1% | max-risk 1.0% | $3086.82 |
| fib_cap2/leg/0.50% | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap2/leg/0.50%+ddguard | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap3/leg/0.50% | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap3/leg/0.50%+ddguard | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap5/leg/0.50% | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap5/leg/0.50%+ddguard | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap8/leg/0.50% | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| fib_cap8/leg/0.50%+ddguard | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| linear_cap3/leg/0.50% | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| linear_cap3/leg/0.50%+ddguard | 72 | 22.4% | 7.9% | 1.0% | max-risk 1.0% | $3060.98 |
| soft_fib3/instrument/0.50% | 72 | 21.7% | 7.7% | 1.1% | max-risk 1.0% | $3041.27 |
| soft_fib3/instrument/0.50%+ddguard | 72 | 21.7% | 7.7% | 1.1% | max-risk 1.0% | $3041.27 |
| soft_fib5/instrument/0.50% | 72 | 21.7% | 7.7% | 1.1% | max-risk 1.0% | $3041.27 |
| soft_fib5/instrument/0.50%+ddguard | 72 | 21.7% | 7.7% | 1.1% | max-risk 1.0% | $3041.27 |
| fixed/account/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fixed/account/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fixed/instrument/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fixed/instrument/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fixed/leg/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fixed/leg/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib3/account/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib3/account/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib3/leg/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib3/leg/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib5/account/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib5/account/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib5/leg/0.50% | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| soft_fib5/leg/0.50%+ddguard | 72 | 20.6% | 7.3% | 1.1% | max-risk 0.5% | $3014.86 |
| fib_cap3/instrument/0.25% | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap3/instrument/0.25%+ddguard | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap5/instrument/0.25% | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap5/instrument/0.25%+ddguard | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap8/instrument/0.25% | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap8/instrument/0.25%+ddguard | 72 | 11.7% | 4.3% | 0.5% | max-risk 0.8% | $2792.17 |
| fib_cap2/account/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap2/account/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap3/account/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap3/account/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap5/account/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap5/account/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap8/account/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap8/account/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| linear_cap3/account/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| linear_cap3/account/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2780.66 |
| fib_cap2/instrument/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2779.99 |
| fib_cap2/instrument/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2779.99 |
| linear_cap3/instrument/0.25% | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2779.99 |
| linear_cap3/instrument/0.25%+ddguard | 72 | 11.2% | 4.1% | 0.5% | max-risk 0.5% | $2779.99 |
| fib_cap2/leg/0.25% | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap2/leg/0.25%+ddguard | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap3/leg/0.25% | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap3/leg/0.25%+ddguard | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap5/leg/0.25% | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap5/leg/0.25%+ddguard | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap8/leg/0.25% | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| fib_cap8/leg/0.25%+ddguard | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| linear_cap3/leg/0.25% | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| linear_cap3/leg/0.25%+ddguard | 72 | 10.7% | 3.9% | 0.5% | max-risk 0.5% | $2768.17 |
| soft_fib3/instrument/0.25% | 72 | 10.4% | 3.8% | 0.5% | max-risk 0.5% | $2759.24 |
| soft_fib3/instrument/0.25%+ddguard | 72 | 10.4% | 3.8% | 0.5% | max-risk 0.5% | $2759.24 |
| soft_fib5/instrument/0.25% | 72 | 10.4% | 3.8% | 0.5% | max-risk 0.5% | $2759.24 |
| soft_fib5/instrument/0.25%+ddguard | 72 | 10.4% | 3.8% | 0.5% | max-risk 0.5% | $2759.24 |
| fixed/account/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| fixed/account/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| fixed/instrument/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| fixed/instrument/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| fixed/leg/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| fixed/leg/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib3/account/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib3/account/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib3/leg/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib3/leg/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib5/account/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib5/account/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib5/leg/0.25% | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |
| soft_fib5/leg/0.25%+ddguard | 72 | 9.9% | 3.6% | 0.5% | max-risk 0.2% | $2747.15 |

## Selected gate policy

fib_cap3/instrument/1.50%

## Four-year confirmation

- fib_cap3/instrument/1.50%: ROI 104.6%, CAGR 19.7%, DD 6.3%, final $5113.98

## Shuffled sequence stress

10,000 random reorderings of the same outcomes; dates are ignored.

| Policy | Paths >15% DD | Median DD | 95th DD | 99th DD | Median final |
|---|---:|---:|---:|---:|---:|
| fib_cap3/instrument/1.50% | 3.3% | 7.4% | 13.9% | 18.0% | $4655 |
| fixed/instrument/1.50% | 0.0% | 5.9% | 9.4% | 11.4% | $4320 |

## Verdict

A policy is not accepted because it wins on the historical order.
It must remain positive on the unchanged confirmation window and
leave sufficient sequence-risk margin in the shuffled stress test.
A capped progression is a risk rule, not a source of predictive edge.
