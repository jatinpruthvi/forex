# TRIAD-R High Stakes Challenge Strategy V2

This repository was missing the canonical specification file required by the source contract tests.
This file is intentionally minimal and references the V2 strategy family used by the project.

## Purpose

This specification is the canonical V2 reference for the challenge-aware strategy stack.
The production-safe implementation is the fail-closed research design under the `TRIAD_R_HS`
source tree and the V3 prototype under `TRIAD_GOD_COMBO_V3`.

## Status

- Project strategy family: V2 baseline and V3 controller prototype
- Safety default: order submission disabled unless explicitly enabled after validation
- Requirement: never ship live execution from unverified code

## Core contract

- One shared account-wide slot must be enforced at runtime.
- Gold and triad legs never compete simultaneously for an active slot without a guarded policy.
- No live order submission is allowed by default.
- Validation gates must be satisfied before any challenge or funded deployment.

## V3 note

The V3 build is intended as a fail-closed portfolio controller prototype that evaluates a one-slot
triad versus gold arbitration model without submitting orders in the default configuration.
