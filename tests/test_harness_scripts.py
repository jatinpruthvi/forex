"""Behavioural spec for two harness-script defects found in the top-25 sweep.

Neither the launcher nor the engine clock can run in this sandbox, so the two
rules are mirrored in Python and pinned:

  1. **`PortfolioLauncher.mq5` — expert-name matching.**
     Four delivered EA names are prefixes of another delivered EA name and both
     members of every pair are in `launch_plan.csv`:

         round4_contestant_b   vs  round4_contestant_b__1_
         round4_contestant_c   vs  round4_contestant_c__1_
         round5_contestant_a   vs  round5_contestant_a_2047
         round5_contestant_b   vs  round5_contestant_b_2048

     A substring test (the old rule) treats each pair as the same EA: one of the
     two is skipped as "already running" and STOP can close the wrong chart.
     The matcher must normalise (drop path + .ex5/.mq5) and compare exactly.

  2. **`EACore.mqh` — the server offset in the Strategy Tester.**
     MT5 documents that in the tester ``TimeGMT()`` always equals the simulated
     ``TimeTradeServer()``, so the auto rule ``server - GMT`` is always 0 there
     - it would silently claim "server == UTC" and shift every news window,
     session window and London day anchor.  The configured winter/EU-DST path is
     the only usable one inside the tester.
"""
from __future__ import annotations

import unittest

# ------------------------------------------------ launcher name matching -----
DELIVERED_PAIRS = [
    ("EA_studyarena_round4_contestant_b", "EA_studyarena_round4_contestant_b__1_"),
    ("EA_studyarena_round4_contestant_c", "EA_studyarena_round4_contestant_c__1_"),
    ("EA_studyarena_round5_contestant_a", "EA_studyarena_round5_contestant_a_2047"),
    ("EA_studyarena_round5_contestant_b", "EA_studyarena_round5_contestant_b_2048"),
]


def expert_key(expert: str) -> str:
    """Mirror of ExpertKey() in PortfolioLauncher.mq5."""
    k = expert
    cut = k.find("\\")
    while cut >= 0:
        k = k[cut + 1:]
        cut = k.find("\\")
    if len(k) > 4 and k[-4:].lower() in (".ex5", ".mq5"):
        k = k[:-4]
    return k


def old_substring_match(a: str, b: str) -> bool:
    """The delivered rule: either name contained in the other."""
    return a in b or b in a


class LauncherNameMatchTests(unittest.TestCase):
    def test_the_four_prefix_pairs_are_different_eas(self):
        for short, long in DELIVERED_PAIRS:
            self.assertNotEqual(expert_key(short), expert_key(long))
            # ...while the rule that shipped called them the same EA
            self.assertTrue(old_substring_match(short, long),
                            f"{short} / {long}: the substring rule must be the defect")

    def test_normalisation_still_accepts_the_same_ea_written_three_ways(self):
        for variant in ("EA_studyarena_round5_contestant_a",
                        "EA_studyarena_round5_contestant_a.ex5",
                        "Experts\\additionalEAs\\EA_studyarena_round5_contestant_a",
                        "Experts\\additionalEAs\\EA_studyarena_round5_contestant_a.ex5"):
            self.assertEqual(expert_key(variant), "EA_studyarena_round5_contestant_a")

    def test_empty_and_foreign_names_never_match(self):
        self.assertEqual(expert_key(""), "")
        self.assertNotEqual(expert_key("SomeOtherEA"), "EA_studyarena_round5_contestant_a")


# ------------------------------------------------ tester server offset -------
CONFIGURED_WINTER = 2          # the delivered default (EACore: winter +2, EU DST)


def configured_offset(utc_dt, eu_dst: bool) -> int:
    return CONFIGURED_WINTER + (1 if eu_dst else 0)


def resolve_offset(auto: bool, in_tester: bool, utc_dt, eu_dst: bool,
                   live_server_minus_gmt: int) -> int:
    """Mirror of the two offset helpers after the fix."""
    if auto and not in_tester:
        return live_server_minus_gmt
    if auto and in_tester:
        # the documented tester behaviour: TimeTradeServer() == TimeGMT() -> 0,
        # so the auto path must fall back to the configured rule
        return configured_offset(utc_dt, eu_dst)
    return configured_offset(utc_dt, eu_dst)


class ServerOffsetPolicyTests(unittest.TestCase):
    def test_auto_in_the_tester_cannot_be_measured(self):
        # engine 3107 (EA_THE5ERS_HIGH_STAKES_RESEARCH) ships serverOffsetAuto=true.
        # In the tester the live difference is always 0; the configured rule must win
        # (summer: +3, winter: +2) - never 0.
        self.assertEqual(resolve_offset(True, True, None, True, live_server_minus_gmt=0), 3)
        self.assertEqual(resolve_offset(True, True, None, False, live_server_minus_gmt=0), 2)

    def test_auto_live_still_reads_the_terminal_clocks(self):
        self.assertEqual(resolve_offset(True, False, None, True, live_server_minus_gmt=3), 3)
        self.assertEqual(resolve_offset(True, False, None, True, live_server_minus_gmt=0), 0)

    def test_configured_path_is_unchanged(self):
        self.assertEqual(resolve_offset(False, True, None, True, live_server_minus_gmt=7), 3)
        self.assertEqual(resolve_offset(False, False, None, False, live_server_minus_gmt=7), 2)

    def test_the_zero_offset_shift_is_the_defect_90_failure_mode(self):
        # With the old rule (auto wins even in the tester) the offset is 0 and every
        # UTC conversion is a no-op: a 13:30 UTC release would be treated as 13:30
        # server instead of 16:30 on a GMT+3 server - three hours away.
        old = 0
        fixed = resolve_offset(True, True, None, True, live_server_minus_gmt=0)
        self.assertNotEqual(old, fixed)
        self.assertEqual(fixed - old, 3)


if __name__ == "__main__":
    unittest.main()
