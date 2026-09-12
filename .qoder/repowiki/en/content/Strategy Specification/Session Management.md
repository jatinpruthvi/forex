# Session Management

<cite>
**Referenced Files in This Document**
- [TRIAD_R_HS.mq5](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5)
</cite>

## Table of Contents
1. Introduction
2. Project Structure
3. Core Components
4. Architecture Overview
5. Detailed Component Analysis
6. Dependency Analysis
7. Performance Considerations
8. Troubleshooting Guide
9. Conclusion

## Introduction
This document explains the session management system used to handle London and New York market sessions for specific instrument combinations. It covers:
- Time windows defined in Europe/London and America/New_York timezones, including DST-aware conversions.
- MT5 server timestamp handling and conversion between UTC and server time.
- Session-based routing: EURUSD and GBPUSD are traded during London sessions; USDJPY is traded during New York sessions.
- Implementation details for session boundary detection, rollover handling, Friday cutoff procedures, and edge cases such as DST transitions and overlapping sessions.

## Project Structure
The session logic is implemented within a single Expert Advisor file that defines:
- Session kinds (London, New York).
- Session runtime state structures holding range and entry windows per session slot.
- Timezone conversion utilities for Europe/London and America/New_York with DST rules.
- Boundary builders that compute range_start/range_end and entry_start/entry_end per civil date and session kind.
- A scanning loop that refreshes each session’s bounds and only considers candidates inside the active entry window.
- Exposure management that enforces session-end exits, Friday flat rules, and rollover safety.

```mermaid
graph TB
subgraph "Session Definitions"
LON["SESSION_LONDON"]
NY["SESSION_NEW_YORK"]
end
subgraph "Time Conversion"
TZL["LondonUtcOffsetSeconds()"]
TZN["NewYorkUtcOffsetSeconds()"]
LWU["LocalWallToUtc()"]
UTS["UtcToServer()"]
STU["ServerToUtc()"]
end
subgraph "Boundaries"
BBD["BuildBoundsForCivilDate()"]
CSB["GetCurrentSessionBounds()"]
end
subgraph "Runtime"
INIT["InitializeSessions()"]
SCAN["ScanForSignals()"]
MANAGE["ManageExposure()"]
end
LON --> TZL
NY --> TZN
TZL --> LWU
TZN --> LWU
LWU --> UTS
UTS --> BBD
BBD --> CSB
CSB --> SCAN
SCAN --> MANAGE
```

**Diagram sources**
- [TRIAD_R_HS.mq5:31-35](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L31-L35)
- [TRIAD_R_HS.mq5:663-701](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L701)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

**Section sources**
- [TRIAD_R_HS.mq5:31-35](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L31-L35)
- [TRIAD_R_HS.mq5:158-178](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L158-L178)
- [TRIAD_R_HS.mq5:663-701](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L701)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

## Core Components
- Session kinds and slots: Two session kinds (London, New York) and three session slots are used to represent two London instruments and one New York instrument. Each slot stores symbol, currencies, kind, enabled flag, priority, and dynamic boundaries (range and entry windows).
- Timezone utilities: DST-aware functions compute offsets for London and New York based on UTC timestamps, then convert local wall times to UTC and finally to MT5 server time using a configured offset.
- Boundary builder: For a given civil date and session kind, computes:
  - London: range 00:00–07:00 Europe/London; entry 07:00–11:00 Europe/London.
  - New York: entry 08:30–11:00 America/New_York; range derived from the corresponding London reference window (07:00–13:00 Europe/London) aligned to the New York entry start.
- Session refresh and scan: Each tick, the EA refreshes session bounds, checks if current server time falls within the entry window, and only then evaluates signals.
- Exposure management: Enforces session-end exits, news blackout windows, rollover flat periods, and Friday cutoffs.

**Section sources**
- [TRIAD_R_HS.mq5:31-35](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L31-L35)
- [TRIAD_R_HS.mq5:158-178](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L158-L178)
- [TRIAD_R_HS.mq5:663-701](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L701)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

## Architecture Overview
The session management architecture centers on timezone-aware boundary computation and strict gating of trading activity to defined entry windows. The flow is:
- Initialize sessions with symbols, kinds, and priorities.
- On each iteration, compute current session bounds using DST-aware conversions and MT5 server time.
- Only consider signal detection when inside the entry window.
- After submission, manage exposure by enforcing session-end exits, news blackout, rollover flat, and Friday cutoff.

```mermaid
sequenceDiagram
participant EA as "EA Loop"
participant Sess as "Session Bounds"
participant Scan as "Signal Scanner"
participant Manage as "Exposure Manager"
EA->>Sess : GetCurrentSessionBounds(session_index, now)
Sess-->>EA : range_start, range_end, entry_start, entry_end
EA->>Scan : DetectPattern(session_index) if now in [entry_start, entry_end)
Scan-->>EA : Candidate or rejection
EA->>Manage : SubmitCandidate() / ManageExposure()
Manage-->>EA : Exit decisions (session_end, friday_flat, rollover_flat, news)
```

**Diagram sources**
- [TRIAD_R_HS.mq5:781-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L781-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

## Detailed Component Analysis

### Timezone Conversions and DST Awareness
- London DST: Uses last Sunday in March and October to determine BST vs GMT offset (+01:00 vs +00:00).
- New York DST: Uses second Sunday in March and first Sunday in November to determine EDT (-04:00) vs EST (-05:00).
- LocalWallToUtc: Converts a local wall time in either zone to UTC by applying standard offset, estimating DST via the target zone’s rules, then re-evaluating DST at the resulting UTC time for correctness across transition boundaries.
- Server conversions: UtcToServer and ServerToUtc apply a configured expected server UTC offset to align with MT5 server time.

```mermaid
flowchart TD
Start(["Local Wall Time"]) --> Standard["Apply Standard Offset"]
Standard --> GuessUTC["Guess UTC"]
GuessUTC --> DSTCheck{"DST Active?"}
DSTCheck --> |Yes| ApplyDST["Apply DST Offset"]
DSTCheck --> |No| KeepStd["Keep Standard Offset"]
ApplyDST --> Recheck["Recompute UTC and Recheck DST"]
KeepStd --> Recheck
Recheck --> Result(["UTC Timestamp"])
```

**Diagram sources**
- [TRIAD_R_HS.mq5:663-691](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L691)

**Section sources**
- [TRIAD_R_HS.mq5:663-701](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L701)

### Session Boundaries and Instrument Routing
- London session:
  - Range window: 00:00–07:00 Europe/London.
  - Entry window: 07:00–11:00 Europe/London.
  - Instruments: EURUSD and GBPUSD.
- New York session:
  - Entry window: 08:30–11:00 America/New_York.
  - Range window: Derived from the corresponding London reference range (07:00–13:00 Europe/London), anchored to the New York entry start.
  - Instrument: USDJPY.

Boundary computation steps:
- Determine local date for the session kind using DST-aware GetLocalDate.
- Build bounds using BuildBoundsForCivilDate, which sets range and entry windows according to session kind.
- Convert all computed UTC times to MT5 server time using UtcToServer.

```mermaid
flowchart TD
Inp["Input: session_index, year, month, day"] --> Kind{"Kind == LONDON?"}
Kind --> |Yes| LRange["range = 00:00–07:00 London"]
LRange --> LEntry["entry = 07:00–11:00 London"]
Kind --> |No| NEntry["entry = 08:30–11:00 New York"]
NEntry --> NRange["range = 07:00–13:00 London<br/>aligned to entry start"]
LEntry --> ToServer["Convert to Server Time"]
NRange --> ToServer
LRange --> ToServer
ToServer --> Out["Output: range_start, range_end, entry_start, entry_end"]
```

**Diagram sources**
- [TRIAD_R_HS.mq5:754-779](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L779)

**Section sources**
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)

### Session-Based Approach for Instrument Combinations
- Initialization assigns:
  - Slot 0: EURUSD, SESSION_LONDON, enabled/priority configurable.
  - Slot 1: GBPUSD, SESSION_LONDON, enabled/priority configurable.
  - Slot 2: USDJPY, SESSION_NEW_YORK, enabled/priority configurable.
- Scanning iterates over sessions, refreshing bounds and only considering candidates within the active entry window.
- Collisions between multiple valid candidates are resolved by configured priority, then cost-to-R, then earliest signal bar, then stable index.

```mermaid
classDiagram
class SessionRuntime {
+string id
+string symbol
+string ccy1
+string ccy2
+ENUM_SESSION_KIND kind
+bool enabled
+int priority
+int local_day_key
+datetime range_start
+datetime range_end
+datetime entry_start
+datetime entry_end
+double range_high
+double range_low
+bool range_ready
+bool consumed
+datetime last_closed_bar
}
class TRIAD_EA {
+InitializeSessions()
+ScanForSignals()
+ManageExposure()
}
TRIAD_EA --> SessionRuntime : "manages up to 3 slots"
```

**Diagram sources**
- [TRIAD_R_HS.mq5:158-178](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L158-L178)
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)

**Section sources**
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)

### Rollover Handling and Friday Cutoff Procedures
- Rollover flat: Positions are closed before rollover using a configurable minutes-before-midnight window plus a safety lead.
- Friday cutoff: Positions are closed after a fixed London-time threshold on Fridays to avoid weekend exposure.
- Missed rollover exposure: The system detects if history was unavailable around rollover and halts safely if necessary, persisting incident keys for auditability.

```mermaid
flowchart TD
CheckNow["Current server time"] --> NearMidnight{"Within rollover flat window?"}
NearMidnight --> |Yes| CloseRoll["Close position: pre_rollover_flat"]
NearMidnight --> |No| FriCheck{"Friday >= threshold?"}
FriCheck --> |Yes| CloseFri["Close position: friday_flat"]
FriCheck --> |No| Continue["Continue managing exposure"]
```

**Diagram sources**
- [TRIAD_R_HS.mq5:3157-3183](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3157-L3183)
- [TRIAD_R_HS.mq5:3290-3428](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3290-L3428)

**Section sources**
- [TRIAD_R_HS.mq5:3157-3183](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3157-L3183)
- [TRIAD_R_HS.mq5:3290-3428](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3290-L3428)

### Edge Cases: DST Transitions and Session Overlaps
- DST transitions:
  - London: Offsets change on last Sundays of March and October; LocalWallToUtc recomputes DST at both guess and final UTC to ensure correct boundaries.
  - New York: Offsets change on second Sunday of March and first Sunday of November; similar recomputation ensures robustness.
- Session overlaps:
  - New York entry window can overlap with London range; the system derives New York range from London’s reference window but gates entries strictly to the New York entry window.
  - Collision handling: If multiple sessions produce candidates simultaneously, priority and cost-to-R resolve the winner; losers are rejected and logged.

```mermaid
sequenceDiagram
participant TZ as "Timezone Utils"
participant B as "Boundary Builder"
participant S as "Scanner"
participant M as "Manager"
TZ->>B : LocalWallToUtc(Zone, WallTime)
B-->>S : entry_start, entry_end (server time)
S->>S : DetectPattern if now in [entry_start, entry_end)
alt Multiple candidates
S->>S : Rank by priority/cost/signal_time
S-->>M : Winner candidate
else Single candidate
S-->>M : Candidate
end
M->>M : Enforce session_end/news/rollover/friday rules
```

**Diagram sources**
- [TRIAD_R_HS.mq5:663-691](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L691)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

**Section sources**
- [TRIAD_R_HS.mq5:663-691](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L663-L691)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

## Dependency Analysis
Key dependencies and relationships:
- Session initialization depends on symbol availability and indicator handles (ATR, H1 EMA). Invalid handles halt or warn accordingly.
- Boundary computation depends on DST-aware timezone utilities and MT5 server offset configuration.
- Scanning depends on refreshed session bounds and news calendar validity.
- Exposure management depends on plan persistence, quote freshness, and risk guards.

```mermaid
graph LR
Init["InitializeSessions()"] --> Handles["ATR/EMA Handles"]
TZ["Timezone Utils"] --> Bounds["BuildBoundsForCivilDate()"]
Bounds --> Scan["ScanForSignals()"]
News["News Calendar"] --> Scan
Scan --> Submit["SubmitCandidate()"]
Submit --> Manage["ManageExposure()"]
Manage --> Guards["Risk Guards & Plan Checks"]
```

**Diagram sources**
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

**Section sources**
- [TRIAD_R_HS.mq5:3950-4001](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3950-L4001)
- [TRIAD_R_HS.mq5:754-789](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L754-L789)
- [TRIAD_R_HS.mq5:4003-4099](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L4003-L4099)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)

## Performance Considerations
- History reads for range and statistics are bounded by expected bar counts and validated against continuity gaps to avoid stale or incomplete data.
- Indicator handles are reused per session slot to minimize overhead.
- Quote freshness checks prevent processing on stale ticks.
- Safety leads reduce boundary misalignment risks near session edges.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and their handling:
- Stale or invalid news calendar: Halts or blocks trading until coverage is sufficient.
- Missing or mismatched trade plan: Deletes pending orders or closes positions and halts to prevent unmanaged exposure.
- Order submission failures: Cleans up any uncertain orders and halts to ensure fail-closed behavior.
- Rollover history unavailable: Halts and requires migration/rebaseline to maintain integrity.
- Friday cutoff and session-end exits: Ensure positions are closed appropriately to avoid unintended weekend exposure.

**Section sources**
- [TRIAD_R_HS.mq5:836-918](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L836-L918)
- [TRIAD_R_HS.mq5:2942-3284](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L2942-L3284)
- [TRIAD_R_HS.mq5:3290-3428](file://MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5#L3290-L3428)

## Conclusion
The session management system implements precise, DST-aware boundaries for London and New York sessions, routing EURUSD/GBPUSD to London and USDJPY to New York. It enforces strict entry windows, manages rollover and Friday cutoffs, and integrates news blackout checks. The design prioritizes safety through fail-closed mechanisms, plan reconciliation, and robust error handling, ensuring reliable operation across DST transitions and overlapping sessions.

[No sources needed since this section summarizes without analyzing specific files]