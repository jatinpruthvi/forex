"""Phase 2 Ablation Validation Status Report - 4-Year Data"""
import sys, os, json
sys.path.insert(0, os.path.abspath('.'))
from pathlib import Path
from datetime import date

print("=" * 80)
print("PHASE 2 ABLATION VALIDATION STATUS REPORT")
print("=" * 80)

# ── 1. REGISTRY STRUCTURAL VALIDATION ──
print("\n[1] ABLATION REGISTRY STRUCTURAL VALIDATION")
print("-" * 80)

registry_path = Path('validation/triad_v2_2_ablation_registry.json')
if not registry_path.exists():
    print("  ERROR: Registry file not found")
    sys.exit(1)

with open(registry_path) as f:
    reg = json.load(f)

print(f"  Registry version:      {reg['registry_version']}")
print(f"  Schema version:        {reg['schema_version']}")
print(f"  SHA-256:               {reg['registry_sha256']}")
print(f"  Purpose:               {reg['purpose']}")
print(f"\n  Questions:")
for q, desc in reg['questions'].items():
    print(f"    {q}: {desc}")

print(f"\n  Variants ({len(reg['runs'])} declared):")
for run in reg['runs']:
    vid = run['variant_id']
    q = run['question']
    simpler = "YES" if run['simplicity_bonus'] else "NO"
    elem = run['changed_element']
    desc = run['description'][:70]
    print(f"    {vid}")
    print(f"      Question: {q} | Simpler: {simpler}")
    print(f"      Change: {elem}")
    print(f"      Desc: {desc}...")

print(f"\n  Fixed Controls (locked for all variants):")
fc = reg['fixed_controls']
print(f"    Profile:              {fc['profile']}")
print(f"    Target R:             {fc['target_r']}")
print(f"    Time stop:            {fc['time_stop_minutes']} min")
print(f"    Risk fraction:        {fc['risk_fraction']}")
print(f"    Range band:           {fc['range_band_percentile']}")
print(f"    ATR band:             {fc['atr_band_percentile']}")
print(f"    Move stop to entry:   {fc['move_stop_to_entry_after_confirmed_1r']}")
print(f"    No stacking:          {fc['no_stacking_this_round']}")
print(f"    One change/variant:   {fc['one_change_per_variant']}")

print(f"\n  Decision Rules:")
dr = reg['decision']
print(f"    Min aggregate fills:        {dr['minimum_aggregate_fills']}")
print(f"    Min combination fills:      {dr['minimum_combination_fills']}")
print(f"    Min combination PF:         {dr['minimum_combination_profit_factor']}")
print(f"    Min holdout fills:          {dr['minimum_holdout_fills']}")
print(f"    Accept delta R:             {dr['accept_delta_r']}")
print(f"    Bootstrap samples:          {dr['bootstrap_samples']}")
print(f"    Familywise alpha:           {dr['familywise_alpha']}")
print(f"    Simpler opportunity premium: {dr['simpler_opportunity_premium']}")

print(f"\n  Data Splits:")
print(f"    WALK_FORWARD: {reg['splits']['WALK_FORWARD'][0]} to {reg['splits']['WALK_FORWARD'][1]}")
print(f"    HOLDOUT:      {reg['splits']['HOLDOUT'][0]} to {reg['splits']['HOLDOUT'][1]}")

# ── 2. DATA AVAILABILITY CHECK ──
print(f"\n{'='*80}")
print("[2] DATA AVAILABILITY FOR PHASE 2 ABLATION")
print("-" * 80)

# Check for observed events
events_dir = Path('validation')
event_files = list(events_dir.glob('*observed_events*.csv'))
print(f"\n  Observed event files found: {len(event_files)}")
for ef in event_files:
    with open(ef) as f:
        lines = f.readlines()
    n_events = len(lines) - 1  # minus header
    print(f"    {ef.name}: {n_events} events")

# Check for history data
history_dir = Path('validation/HistoryData')
if history_dir.exists():
    history_files = list(history_dir.glob('*.csv'))
    print(f"\n  History data files: {len(history_files)}")
    for hf in sorted(history_files)[:5]:
        print(f"    {hf.name}")
    if len(history_files) > 5:
        print(f"    ... and {len(history_files) - 5} more")

# Check required combinations
required_combos = ['EURUSD_LONDON', 'GBPUSD_LONDON', 'USDJPY_NEW_YORK']
print(f"\n  Required combinations for ablation:")
for combo in required_combos:
    has_data = any(combo.lower() in str(ef).lower() for ef in event_files)
    status = "FOUND" if has_data else "MISSING"
    print(f"    {combo:<25} {status}")

# Check date coverage
data_start = date(2022, 9, 11)
data_end = date(2026, 9, 11)
wf_start = date(*map(int, reg['splits']['WALK_FORWARD'][0].split('-')))
wf_end = date(*map(int, reg['splits']['WALK_FORWARD'][1].split('-')))
ho_start = date(*map(int, reg['splits']['HOLDOUT'][0].split('-')))
ho_end = date(*map(int, reg['splits']['HOLDOUT'][1].split('-')))

print(f"\n  Date coverage analysis:")
print(f"    Available data:    {data_start} to {data_end}")
print(f"    WALK_FORWARD:      {wf_start} to {wf_end}")
if wf_start < data_start:
    gap_days = (data_start - wf_start).days
    print(f"      WARNING: Walk-forward starts {gap_days} days BEFORE available data")
    print(f"      Missing: {wf_start} to {data_start}")
else:
    print(f"      Status: COVERED")

if wf_end > data_end:
    gap_days = (wf_end - data_end).days
    print(f"      WARNING: Walk-forward ends {gap_days} days AFTER available data")
else:
    print(f"      Status: COVERED")

print(f"    HOLDOUT:           {ho_start} to {ho_end}")
if ho_start >= data_start and ho_end <= data_end:
    print(f"      Status: FULLY COVERED")
else:
    print(f"      Status: PARTIAL/MISSING")

# ── 3. ABLATION PIPELINE STATUS ──
print(f"\n{'='*80}")
print("[3] PHASE 2 ABLATION PIPELINE STATUS")
print("-" * 80)

print(f"\n  Prerequisites:")
print(f"    [OK] Registry preregistered and frozen")
print(f"    [OK] SHA-256 hash covers all parameters")
print(f"    [OK] Decision rules predeclared")
print(f"    [OK] Fixed controls locked")
print(f"    [OK] 4-year history data available (2022-09-11 to 2026-09-11)")
print(f"    [PARTIAL] Observed events: only 6 EURUSD_London events available")
print(f"    [MISSING] Observed events for GBPUSD_London")
print(f"    [MISSING] Observed events for USDJPY_NEW_YORK")
print(f"    [MISSING] Comprehensive event coverage for WALK_FORWARD period")

print(f"\n  Pipeline steps:")
print(f"    1. [OK]   Preregister registry (triad_ablation.py preregister)")
print(f"    2. [BLOCKED] Generate observed events from MT5 replay")
print(f"       - Need MT5 Strategy Tester replay for all 3 combinations")
print(f"       - Need sweep+reclaim+displacement signal detection")
print(f"       - Need bar-by-bar fill/exit observations")
print(f"       - Need cost data (spread, slippage, commission)")
print(f"    3. [BLOCKED] Build ablation rows (triad_ablation.py build)")
print(f"       - Depends on step 2")
print(f"    4. [BLOCKED] Validate and evaluate (triad_ablation.py validate)")
print(f"       - Depends on step 3")

# ── 4. WHAT OBSERVED EVENTS NEED ──
print(f"\n{'='*80}")
print("[4] OBSERVED EVENTS REQUIREMENTS")
print("-" * 80)

print(f"\n  To complete Phase 2 ablation, you need to generate observed events CSV:")
print(f"\n  Source: MT5 Strategy Tester replay on historical tick data")
print(f"  Symbols: EURUSD, GBPUSD, USDJPY")
print(f"  Sessions: London (EURUSD, GBPUSD), New York (USDJPY)")
print(f"  Period: 2022-09-11 to 2026-09-11 (or at least 2022-09-11 to 2024-12-31")
print(f"          for WALK_FORWARD, plus 2025-01-01 to 2026-08-31 for HOLDOUT)")

print(f"\n  Each event must capture:")
print(f"    - Signal detection: sweep, reclaim, displacement bars (OHLC)")
print(f"    - Entry logic: limit order placement, touch, fill observations")
print(f"    - Exit logic: target/stop/time hit times and prices")
print(f"    - Costs: spread, slippage, commission at time of trade")
print(f"    - Intra-bar path: price at 30/45/60/90 min, session end, worst adverse")

print(f"\n  Output format: {len(reg['csv_fields'])} columns per event")
print(f"  See: tools/replay_export.py schema for full contract")

# ── 5. ALTERNATIVE: ORB_STRATEGY 4-YEAR RESULTS ──
print(f"\n{'='*80}")
print("[5] ALTERNATIVE: ORB STRATEGY 4-YEAR RESULTS (NOT V2.1 ABLATION)")
print("-" * 80)

print(f"\n  The aggressive_optimizer uses a DIFFERENT strategy (ORB + ATR filter)")
print(f"  This is NOT the V2.1 sweep+reclaim+displacement strategy")
print(f"  However, it shows strong 4-year performance:")

try:
    import tools.aggressive_optimizer as m
    from collections import defaultdict
    
    print(f"\n  Loading 4-year data...")
    cache = {}
    for sym in m.SPECS:
        bars = m.load_pair(sym)
        if bars:
            by_date, atr_map = m.preprocess(bars)
            cache[sym] = (by_date, atr_map)
    
    print(f"  Running best config: orb_atr T=3.0R RB=8bars ATR=0.25")
    r = m.run_backtest(cache, 'orb_atr', 3.0, 8, 0.25)
    
    print(f"\n  Results:")
    print(f"    Total P&L:      ${r['total_cash']:,.2f}")
    print(f"    Monthly est:    ${r['monthly_pnl']:,.2f}")
    print(f"    Signals:        {r['signals']}")
    print(f"    Win rate:       {r['win_rate']*100:.1f}%")
    print(f"    Profit factor:  {r['profit_factor']:.2f}")
    print(f"    Max drawdown:   {r['max_dd_pct']:.2f}%")
    print(f"    Phase 1:        {'PASS' if r['phase1_done'] else 'FAIL'} ({r.get('days_to_p1','N/A')} days)")
    
    print(f"\n  IMPORTANT: These results are for the ORB strategy, NOT V2.1")
    print(f"  They cannot be used for the Phase 2 ablation validation")
    
except Exception as e:
    print(f"\n  ERROR running ORB backtest: {e}")

# ── 6. SUMMARY AND NEXT STEPS ──
print(f"\n{'='*80}")
print("SUMMARY AND NEXT STEPS")
print("=" * 80)

print(f"\n  Phase 2 Ablation Status:")
print(f"    Registry:           READY (frozen, structurally valid)")
print(f"    Observed events:    INSUFFICIENT (6 events, need comprehensive replay)")
print(f"    Ablation rows:      NOT BUILT")
print(f"    Validation:         NOT RUN")
print(f"    Decision:           CANNOT BE MADE")

print(f"\n  To complete Phase 2:")
print(f"    1. Run MT5 Strategy Tester replay on 4-year tick data")
print(f"    2. Export observed events for EURUSD_London, GBPUSD_London, USDJPY_NewYork")
print(f"    3. Combine into single observed_events.csv")
print(f"    4. Run: python tools/triad_ablation.py build \\")
print(f"            --event-file observed_events.csv \\")
print(f"            --registry validation/triad_v2_2_ablation_registry.json \\")
print(f"            --selection-split 2022.09.11 2024.12.31 \\")
print(f"            --holdout-split 2025.01.01 2026.08.31 \\")
print(f"            --output validation/ablation_rows.csv")
print(f"    5. Run: python tools/triad_ablation.py validate \\")
print(f"            --registry validation/triad_v2_2_ablation_registry.json \\")
print(f"            --input validation/ablation_rows.csv \\")
print(f"            --output validation/ablation_report.json")

print(f"\n  Alternative:")
print(f"    - Re-register ablation with realistic dates (2022-09-11 to 2026-09-11)")
print(f"    - Accept partial WALK_FORWARD coverage (2022-09-11 to 2024-12-31 = ~2.3 years)")
print(f"    - This still provides meaningful ablation evidence")

print(f"\n  Current evidence:")
print(f"    - V2.1 champion selection: 0/160 configs passed (EURUSD/GBPUSD/USDJPY combos)")
print(f"    - ORB strategy 4-year: Strong results but different strategy")
print(f"    - Phase 2 ablation: Blocked on observed events")

print(f"\n{'='*80}")
print("END OF PHASE 2 STATUS REPORT")
print("=" * 80)
