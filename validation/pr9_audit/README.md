# PR #9 audit harness

Evidence for [`findings_pr9_m1_review.md`](../../findings_pr9_m1_review.md).

```bash
python3 validation/pr9_audit/run_all.py          # ~3 min
python3 validation/pr9_audit/run_all.py --quick  # ~30 s, skips the 24-config grid
```

| File | Produces |
|---|---|
| `m1_challenge_sim.py` | engine: exact `tools/m1_holy_grail.py` equivalent + costs, lot rounding, The5ers rule gates, walk-forward |
| `step1_signal_stats.py` | ATR / stop-distance / cost-as-%-of-1R distributions |
| `step2_verify_and_cost.py` | **A** replication check vs published numbers · **B** same trades + real costs |
| `step3_rules_and_walkforward.py` | **C** is the 12.62% DD really post-pass · **D** qualifying days · **E** cost break-even · **F** 120-start-date walk-forward |
| `step4_sizing_and_scale.py` | **G** lot/margin feasibility · **H** optimizer runtime |
| `step5_portfolio_risk.py` | 10-pair concurrency, aggregate risk, trades/day, floor breach |
| `step6_optimizer_grid.py` | full 24-config grid under the PR's own leaderboard filter |
| `step7_gate12.py` | **I** the 12-item go/no-go gate scorecard |
| `step8_breakeven.py` | **J** fine cost break-even · **K** personal −5% DD stop |
| `step9_fills.py` | **L** entry/exit fill realism (gap-through stops and targets) |

Run from the repo root. No third-party dependencies — standard library only,
matching the repo convention.
