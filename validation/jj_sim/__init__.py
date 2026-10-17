"""JJ Simon 1-Minute Fair Pricing — Prop-Firm Pass-Rate Simulator.

Import entry points:

    from validation.jj_sim import simulate, FirmRules, generate_synthetic_m1, load_m1_csv

Run the CLI with:

    python3 -m validation.jj_sim.simulator --synthetic 300 --accounts 50 --config eval_1to1_5
"""

from .simulator import (
    FirmRules,
    Side,
    SignalType,
    Signal,
    Trade,
    Account,
    FairPriceModel,
    SimulationResult,
    Window,
    ny_window,
    load_m1_csv,
    load_news_csv,
    generate_synthetic_m1,
    simulate,
    main,
)

__all__ = [
    "FirmRules",
    "Side",
    "SignalType",
    "Signal",
    "Trade",
    "Account",
    "FairPriceModel",
    "SimulationResult",
    "Window",
    "ny_window",
    "load_m1_csv",
    "load_news_csv",
    "generate_synthetic_m1",
    "simulate",
    "main",
]
