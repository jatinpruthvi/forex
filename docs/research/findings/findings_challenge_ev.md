# Structural ROI without a market edge: expected value of prop challenges (2026-09-30)

> **Superseded (2026-09-30):** this coin-flip model is optimistic; see `findings_challenge_real.md` (real price paths, firm risk limits): the idea is not validated.

No strategy validated in 210 trials (see the other findings). This note asks a different question: with **no edge at all** (a fair random walk, only a cost drag), what do the challenge rules themselves imply? `tools/challenge_ev.py` simulates one bracket trade a day, no time limit, win probability set so expectancy = -c R.

Idea: a fair game reaches +10% before -10% about half the time whatever the bet size, few large bets avoid cost drag, and a funded account pays only on profits while the firm absorbs losses (the payout is truncated below at zero).

Result (assumed rule sets, see script; EV per attempt, net of fee, 5 payout rounds cap):

| Firm-style rule set | P(pass all steps) | P(funded round +5%/+10% before floor) | EV at 0.05R drag | EV at 0.10R drag |
|---|---|---|---|---|
| 2-step 10%/5%, 10% static, 80% split (The5ers High Stakes New) | 0.26 | 0.61 | +1.5x fee | +0.8x fee |
| 2-step 8%/5%, 10% static, 80% split (High Stakes Classic) | 0.26 | 0.61 | +1.3x fee | +0.7x fee |
| 2-step 10%/5%, fee refunded at first payout (FTMO-style) | 0.26 | 0.60 | +0.7x fee | +0.3x fee |
| 2-step 8%/5%, 90% split, fee refund | 0.26 | 0.60 | +1.5x fee | +0.9x fee |
| 3-step 6/6/6, 5% floor, 50% split (The5ers Bootcamp) | 0.08 | 0.34 | -0.8x fee | -0.9x fee |
| 1-step 10%, 6% floor, 50% split (Hyper Growth) | 0.38 | 0.37 | +0.1x fee | -0.2x fee |

Best design in every case: risk about 2.5% of the account per trade (4.5% where the daily limit allows), 2:1 payoff, one trade a day. Small-risk designs (1%) almost never finish.

Caveats (all important): it assumes the firm accepts this style (gambling, consistency or max-risk clauses can void it), payouts are honoured, spreads are as modelled, and the trader really is at zero edge; a worse-than-zero edge or wider real spreads (see `findings_tick_rollover.md`: retail spreads 2-3x my raw assumption) move every row down. About three in four attempts lose the fee. Fees and rules quoted in web sources disagree with each other, verify on the firm's site.
