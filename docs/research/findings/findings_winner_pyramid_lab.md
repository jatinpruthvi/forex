# Winner-Pyramiding Lab — Research Only

One TRIAD add is allowed only after a profitable move; the base stop is
moved to breakeven before the add. No losing-position averaging is used.
Risk is the basket's initial full-stop budget. All runs use raw costs,
a 0.10R adverse stop reserve, one account-wide slot, and a 15% DD halt.

## Gate results

| Config | Risk | Trades | ROI | CAGR | DD | PF | Add rate | Final |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| base_control | 1.5% | 122 | 58.9% | 17.8% | 6.1% | 1.83 | 0.0% | $3972.81 |
| p0.75_retest_close | 1.5% | 122 | 42.9% | 13.5% | 4.9% | 1.60 | 27.0% | $3572.69 |
| base_control | 1.0% | 122 | 36.2% | 11.6% | 3.9% | 1.82 | 0.0% | $3405.23 |
| p0.75_next_open_close | 1.5% | 122 | 35.7% | 11.4% | 4.9% | 1.50 | 28.7% | $3393.61 |
| p0.25_retest_close | 1.5% | 122 | 30.6% | 9.9% | 7.8% | 1.50 | 25.4% | $3265.94 |
| p0.5_retest_close | 1.5% | 122 | 29.9% | 9.7% | 6.8% | 1.44 | 28.7% | $3247.08 |
| p0.5_next_open_close | 1.5% | 122 | 29.3% | 9.5% | 6.7% | 1.44 | 37.7% | $3233.53 |
| p0.25_retest_touch | 1.5% | 123 | 29.2% | 9.5% | 6.2% | 2.01 | 17.1% | $3229.06 |
| p0.25_next_open_close | 1.5% | 122 | 27.9% | 9.1% | 8.5% | 1.44 | 38.5% | $3197.04 |
| p0.75_retest_close | 1.0% | 122 | 26.8% | 8.8% | 3.1% | 1.59 | 27.0% | $3171.19 |
| p0.75_next_open_close | 1.0% | 122 | 23.4% | 7.7% | 3.3% | 1.51 | 28.7% | $3084.25 |
| p0.25_next_open_touch | 1.5% | 123 | 22.1% | 7.3% | 6.5% | 1.73 | 19.5% | $3053.68 |
| p0.25_retest_close | 1.0% | 122 | 19.5% | 6.5% | 5.2% | 1.50 | 25.4% | $2987.82 |
| p0.75_retest_touch | 1.5% | 122 | 19.5% | 6.5% | 6.7% | 1.33 | 32.0% | $2987.54 |
| p0.5_retest_close | 1.0% | 122 | 18.8% | 6.3% | 4.6% | 1.43 | 28.7% | $2970.48 |
| p0.5_next_open_close | 1.0% | 122 | 18.7% | 6.3% | 4.4% | 1.43 | 37.7% | $2968.04 |
| p0.25_retest_touch | 1.0% | 123 | 18.5% | 6.2% | 4.2% | 2.03 | 17.1% | $2962.96 |
| p0.25_next_open_close | 1.0% | 122 | 18.1% | 6.1% | 5.6% | 1.44 | 38.5% | $2952.48 |
| base_control | 0.5% | 122 | 15.7% | 5.3% | 1.9% | 1.77 | 0.0% | $2893.42 |
| p0.25_next_open_touch | 1.0% | 123 | 14.3% | 4.9% | 4.4% | 1.75 | 19.5% | $2857.97 |
| p0.5_retest_touch | 1.5% | 122 | 13.2% | 4.5% | 7.7% | 1.29 | 26.2% | $2829.70 |
| p0.75_retest_touch | 1.0% | 122 | 13.1% | 4.5% | 4.4% | 1.34 | 32.0% | $2827.12 |
| p0.75_next_open_touch | 1.5% | 122 | 12.6% | 4.3% | 8.5% | 1.23 | 14.8% | $2816.19 |
| p0.75_retest_close | 0.5% | 122 | 11.2% | 3.8% | 1.5% | 1.53 | 27.0% | $2778.96 |
| p0.75_next_open_close | 0.5% | 122 | 9.2% | 3.2% | 1.6% | 1.44 | 27.9% | $2728.89 |
| p0.5_retest_touch | 1.0% | 122 | 8.7% | 3.0% | 5.1% | 1.29 | 26.2% | $2717.73 |
| p0.25_retest_touch | 0.5% | 123 | 8.1% | 2.8% | 2.1% | 1.99 | 17.1% | $2703.00 |
| p0.25_retest_close | 0.5% | 122 | 8.0% | 2.8% | 2.5% | 1.44 | 25.4% | $2700.41 |
| p0.75_next_open_touch | 1.0% | 122 | 8.0% | 2.8% | 5.7% | 1.23 | 14.8% | $2700.23 |
| p0.5_next_open_close | 0.5% | 122 | 7.7% | 2.6% | 2.2% | 1.37 | 37.7% | $2691.49 |
| p0.5_retest_close | 0.5% | 122 | 7.7% | 2.6% | 2.2% | 1.38 | 28.7% | $2691.35 |
| p0.25_next_open_close | 0.5% | 122 | 7.6% | 2.6% | 2.8% | 1.39 | 38.5% | $2691.15 |
| p0.25_next_open_touch | 0.5% | 123 | 6.4% | 2.2% | 2.2% | 1.72 | 19.5% | $2660.60 |
| p0.75_retest_touch | 0.5% | 122 | 5.3% | 1.8% | 2.2% | 1.29 | 32.0% | $2631.80 |
| p0.5_next_open_touch | 1.5% | 122 | 4.2% | 1.5% | 8.2% | 1.09 | 21.3% | $2604.25 |
| p0.5_retest_touch | 0.5% | 122 | 3.5% | 1.2% | 2.6% | 1.25 | 26.2% | $2587.54 |
| p0.75_next_open_touch | 0.5% | 122 | 3.2% | 1.1% | 2.8% | 1.19 | 14.8% | $2580.34 |
| p0.5_next_open_touch | 1.0% | 122 | 2.5% | 0.9% | 5.5% | 1.08 | 21.3% | $2561.27 |
| p0.5_next_open_touch | 0.5% | 122 | 0.6% | 0.2% | 2.8% | 1.04 | 21.3% | $2514.50 |

## Selected configuration

base_control         risk= 1.5% n=122 WR= 54.9% PF= 1.83 ROI=   58.9% CAGR= 17.8% DD=  6.1% add=  0.0% final=$ 3972.81 

## Four-year confirmation

base_control         risk= 1.5% n=171 WR= 51.5% PF= 1.51 ROI=   53.3% CAGR= 11.3% DD=  9.4% add=  0.0% final=$ 3831.76 
base_control         risk= 1.5% n=171 WR= 51.5% PF= 1.51 ROI=   53.3% CAGR= 11.3% DD=  9.4% add=  0.0% final=$ 3831.76 
base_control         risk= 1.5% n=171 WR= 51.5% PF= 1.51 ROI=   53.3% CAGR= 11.3% DD=  9.4% add=  0.0% final=$ 3831.76 

## Decision

The gate selection is not accepted unless the unchanged configuration
remains positive under the confirmation run and its drawdown remains
inside the personal-account ceiling. This is still research evidence,
not a live-trading authorization.
