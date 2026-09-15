"""Step 9: the PR books exits at the exact stop/target price. Measure how often
   the real next-bar open would have gapped through that price."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m1_challenge_sim import build_candidates, load_m1_data, DATA, PIP

bars = load_m1_data(DATA)
cands = build_candidates(bars, 2.5, 1.5, 1.5, 5, day_offset_hours=0)

entry_gap, stop_gap, tp_gap = [], [], []
n_stop_gap = n_tp_gap = 0
for c in cands:
    nb = bars[c.i + 1] if c.i + 1 < len(bars) else None
    if nb:
        entry_gap.append(abs(nb.open - c.entry) / PIP)
    ex = bars[c.exit_i]
    if c.timed_out:
        continue
    if not c.win:
        # long stop is a bid <= stop; short stop is a bid >= stop
        jumped = (c.direction == 1 and ex.open <= c.stop) or (c.direction == -1 and ex.open >= c.stop)
        if jumped:
            n_stop_gap += 1
            stop_gap.append(abs(ex.open - c.stop) / PIP)
    else:
        jumped = (c.direction == 1 and ex.open >= c.target) or (c.direction == -1 and ex.open <= c.target)
        if jumped:
            n_tp_gap += 1
            tp_gap.append(abs(ex.open - c.target) / PIP)

resolved = sum(1 for c in cands if not c.timed_out)
nstop = sum(1 for c in cands if not c.timed_out and not c.win)
ntp = sum(1 for c in cands if not c.timed_out and c.win)
entry_gap.sort()
print("=" * 96)
print("L. FILL-REALISM AUDIT (the PR assumes zero slippage on both entry and exit)")
print("=" * 96)
print(f"  entry: PR fills at the trigger bar's CLOSE. The next bar's open differs by")
print(f"         median {entry_gap[len(entry_gap)//2]:.2f} pips, p95 {entry_gap[int(.95*(len(entry_gap)-1))]:.2f} pips, "
      f"max {entry_gap[-1]:.2f} pips")
print(f"  stops: {n_stop_gap}/{nstop} losing trades ({n_stop_gap/nstop*100:.1f}%) open BEYOND the stop")
if stop_gap:
    stop_gap.sort()
    print(f"         -> booked at the stop price instead of the real fill; extra slippage "
          f"median {stop_gap[len(stop_gap)//2]:.2f} pips, max {stop_gap[-1]:.2f} pips")
print(f"  targets: {n_tp_gap}/{ntp} winning trades ({n_tp_gap/ntp*100:.1f}%) open BEYOND the target")
if tp_gap:
    tp_gap.sort()
    print(f"           -> the PR books only the target price, forfeiting gap-through profit "
              f"median {tp_gap[len(tp_gap)//2]:.2f} pips")
print(f"\n  median stop distance is 1.11 pips, so a {stop_gap[len(stop_gap)//2]:.2f}-pip median "
      f"gap-through is {stop_gap[len(stop_gap)//2]/1.11*100:.0f}% of 1R of unmodelled extra loss.")
