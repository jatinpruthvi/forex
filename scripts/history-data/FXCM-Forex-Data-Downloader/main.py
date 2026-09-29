#!/usr/bin/env python3
"""Download recent FXCM M5 bid candles into the repository's common CSV format.

FXCM's REST API requires an access token (read from FXCM_API_TOKEN by default).
The API has a limited M5 lookback, so the default is a conservative 55-day window.
Each request covers at most one week, writes a resumable chunk atomically, and is
throttled before the next request.
"""

import argparse
import csv
import math
import os
import re
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

CSV_HEADER = ['timestamp', 'open', 'high', 'low', 'close', 'volume']
TIMEFRAME = 'm5'
MAX_LOOKBACK_DAYS = 56
DEFAULT_LOOKBACK_DAYS = 55
REQUEST_PAUSE_SECONDS = float(os.environ.get('FXCM_REQUEST_PAUSE_SECONDS', '1.25'))
MAX_RATE_LIMIT_RETRIES = 3

PAIRS = {
    'eurusd': 'EUR/USD',
    'usdjpy': 'USD/JPY',
    'gbpusd': 'GBP/USD',
    'xauusd': 'XAU/USD',
    'eurgbp': 'EUR/GBP',
    'eurjpy': 'EUR/JPY',
    'audusd': 'AUD/USD',
    'usdcad': 'USD/CAD',
    'nzdusd': 'NZD/USD',
    'usdchf': 'USD/CHF',
    'gbpjpy': 'GBP/JPY',
}

BASE_DIR = Path(__file__).resolve().parents[1]
CHUNK_DIR = BASE_DIR / 'dukascopy-node' / 'm5-chunks'
OUT_DIR = BASE_DIR / 'dukascopy-node' / 'm5-data'


def parse_date(value: str, name: str) -> date:
    try:
        parsed = datetime.strptime(value, '%Y-%m-%d').date()
    except (TypeError, ValueError) as exc:
        raise ValueError(f'{name} must be a valid YYYY-MM-DD date; got {value!r}') from exc
    if parsed.strftime('%Y-%m-%d') != value:
        raise ValueError(f'{name} must be formatted as YYYY-MM-DD; got {value!r}')
    return parsed


def default_range(today: date = None) -> Tuple[date, date]:
    today = today or datetime.utcnow().date()
    return today - timedelta(days=DEFAULT_LOOKBACK_DAYS), today


def build_chunks(start: date, end: date) -> List[Tuple[date, date]]:
    """Split [start, end) into week-aligned requests to stay below candle caps."""
    if end <= start:
        raise ValueError(f'end date {end} must be after start date {start}')

    chunks = []
    cursor = start
    # Keep the initial partial week, then align later chunks to Monday so cached
    # weeks remain reusable when the rolling recent-history window advances.
    days_to_monday = (7 - cursor.weekday()) % 7 or 7
    boundary = min(cursor + timedelta(days=days_to_monday), end)
    chunks.append((cursor, boundary))
    cursor = boundary
    while cursor < end:
        boundary = min(cursor + timedelta(days=7), end)
        chunks.append((cursor, boundary))
        cursor = boundary
    return chunks


def valid_csv(path: Path, allow_empty: bool = True) -> bool:
    try:
        with path.open('r', newline='', encoding='utf-8') as stream:
            reader = csv.reader(stream)
            if next(reader, None) != CSV_HEADER:
                return False
            row_count = 0
            for row in reader:
                if len(row) != 6:
                    return False
                int(row[0])
                for value in row[1:]:
                    if not math.isfinite(float(value)):
                        return False
                row_count += 1
            return allow_empty or row_count > 0
    except (OSError, ValueError, csv.Error):
        return False


def chunk_path(pair: str, start: date, end: date) -> Path:
    return CHUNK_DIR / f'fxcm-{pair}-m5-{start.isoformat()}_{end.isoformat()}.csv'


def output_path(pair: str, start: date, end: date) -> Path:
    return OUT_DIR / f'fxcm-{pair}-m5-{start.isoformat()}_{end.isoformat()}.csv'


def as_timestamp_ms(value) -> int:
    import pandas as pd

    timestamp = pd.Timestamp(value)
    if timestamp.tzinfo is None:
        timestamp = timestamp.tz_localize('UTC')
    else:
        timestamp = timestamp.tz_convert('UTC')
    return int(timestamp.value // 1_000_000)


def normalized_rows(frame, start_ms: int, end_ms: int) -> List[Sequence[float]]:
    rows = {}
    if frame is None or frame.empty:
        return []

    required = ('bidopen', 'bidhigh', 'bidlow', 'bidclose')
    missing = [name for name in required if name not in frame.columns]
    if missing:
        raise ValueError(f'FXCM response is missing bid columns: {", ".join(missing)}')

    for index, candle in frame.iterrows():
        timestamp = as_timestamp_ms(index)
        if timestamp < start_ms or timestamp >= end_ms:
            continue
        open_price = float(candle['bidopen'])
        high_price = float(candle['bidhigh'])
        low_price = float(candle['bidlow'])
        close_price = float(candle['bidclose'])
        volume_value = candle.get('tickqty', 0)
        volume = float(volume_value) if volume_value is not None else 0.0
        if not all(math.isfinite(value) for value in (open_price, high_price, low_price, close_price)):
            continue
        if not math.isfinite(volume):
            volume = 0.0
        if min(open_price, high_price, low_price, close_price) <= 0:
            continue
        rows[timestamp] = (timestamp, open_price, high_price, low_price, close_price, volume)
    return [rows[timestamp] for timestamp in sorted(rows)]


def write_csv_atomic(path: Path, rows: Iterable[Sequence[float]]) -> None:
    temporary = path.with_suffix(path.suffix + '.part')
    with temporary.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream, lineterminator='\n')
        writer.writerow(CSV_HEADER)
        writer.writerows(rows)
    os.replace(temporary, path)


def fetch_week(connection, instrument: str, start: date, end: date) -> List[Sequence[float]]:
    import pandas as pd

    # fxcmpy's wrapper converts naive datetimes to Unix seconds; Actions runners
    # use UTC, so these naive midnight values represent UTC boundaries.
    start_dt = datetime.combine(start, datetime.min.time())
    end_exclusive = datetime.combine(end, datetime.min.time())
    end_inclusive = end_exclusive - timedelta(seconds=1)
    start_ms = int(pd.Timestamp(start_dt, tz='UTC').value // 1_000_000)
    end_ms = int(pd.Timestamp(end_exclusive, tz='UTC').value // 1_000_000)

    for attempt in range(MAX_RATE_LIMIT_RETRIES + 1):
        try:
            frame = connection.get_candles(
                instrument,
                period=TIMEFRAME,
                number=10000,
                start=start_dt,
                end=end_inclusive,
            )
            return normalized_rows(frame, start_ms, end_ms)
        except Exception as exc:
            message = str(exc)
            rate_limited = re.search(r'\b429\b|too many requests|rate.?limit', message, re.I)
            if not rate_limited or attempt >= MAX_RATE_LIMIT_RETRIES:
                raise
            pause = min(60 * (2 ** attempt), 15 * 60)
            print(
                f'FXCM rate limit for {instrument} {start}..{end}; '
                f'waiting {pause}s before retry {attempt + 1}/{MAX_RATE_LIMIT_RETRIES}',
                file=sys.stderr,
                flush=True,
            )
            time.sleep(pause)

    return []


def assemble(pair: str, chunks: Sequence[Tuple[date, date]], start: date, end: date) -> Tuple[Path, int]:
    rows = {}
    for chunk_start, chunk_end in chunks:
        path = chunk_path(pair, chunk_start, chunk_end)
        if not valid_csv(path):
            raise RuntimeError(f'missing or invalid FXCM chunk: {path}')
        with path.open('r', newline='', encoding='utf-8') as stream:
            reader = csv.reader(stream)
            next(reader, None)
            for row in reader:
                timestamp = int(row[0])
                rows[timestamp] = row

    ordered = [rows[timestamp] for timestamp in sorted(rows)]
    if not ordered:
        raise RuntimeError(f'FXCM returned no M5 candles for {pair} in {start}..{end}')
    final_path = output_path(pair, start, end)
    write_csv_atomic(final_path, ordered)
    return final_path, len(ordered)


def download(token: str, start: date, end: date, symbols: Sequence[str] = None) -> None:
    if not token:
        raise ValueError('FXCM_API_TOKEN is missing; add it as a GitHub Actions secret (do not commit it).')
    if end <= start:
        raise ValueError('HISTORY_TO must be after HISTORY_FROM')
    earliest_allowed = datetime.utcnow() - timedelta(days=MAX_LOOKBACK_DAYS)
    requested_start = datetime.combine(start, datetime.min.time())
    if requested_start < earliest_allowed:
        safe_from = (datetime.utcnow().date() - timedelta(days=DEFAULT_LOOKBACK_DAYS)).isoformat()
        raise ValueError(
            f'FXCM M5 history is limited to about {MAX_LOOKBACK_DAYS} days back. '
            f'Request starts at {start}; use a start date on or after {safe_from}.'
        )

    selected = [symbol.lower() for symbol in (symbols or PAIRS.keys())]
    unknown = [symbol for symbol in selected if symbol not in PAIRS]
    if unknown:
        raise ValueError(f'Unsupported pair(s): {", ".join(unknown)}')

    CHUNK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    import fxcmpy

    connection = fxcmpy.fxcmpy(access_token=token, log_level='error')
    try:
        available = set(connection.get_instruments_for_candles())
        for pair in selected:
            instrument = PAIRS[pair]
            if instrument not in available:
                raise RuntimeError(
                    f'{instrument} is not available for FXCM candles; '
                    'check the account/API instrument list.'
                )

            final_path = output_path(pair, start, end)
            if valid_csv(final_path, allow_empty=False):
                print(f'SKIP {pair}: complete file already exists at {final_path}', flush=True)
                continue

            chunks = build_chunks(start, end)
            print(f'FXCM {pair}: {instrument}, {len(chunks)} weekly chunks, {start} -> {end}', flush=True)
            for chunk_start, chunk_end in chunks:
                path = chunk_path(pair, chunk_start, chunk_end)
                if valid_csv(path):
                    print(f'  SKIP {chunk_start}..{chunk_end} (cached)', flush=True)
                    continue

                print(f'  FETCH {chunk_start}..{chunk_end}', flush=True)
                rows = fetch_week(connection, instrument, chunk_start, chunk_end)
                write_csv_atomic(path, rows)
                print(f'  SAVED {len(rows)} rows -> {path.name}', flush=True)
                time.sleep(REQUEST_PAUSE_SECONDS)

            final_path, row_count = assemble(pair, chunks, start, end)
            print(f'DONE {pair}: {row_count} rows -> {final_path}', flush=True)
    finally:
        connection.close()


def main() -> int:
    default_start, default_end = default_range()
    parser = argparse.ArgumentParser(description='Download recent FXCM M5 candles as resumable bid OHLCV CSVs.')
    parser.add_argument('--from', dest='from_date', default=os.environ.get('HISTORY_FROM') or default_start.isoformat())
    parser.add_argument('--to', dest='to_date', default=os.environ.get('HISTORY_TO') or default_end.isoformat())
    parser.add_argument('--token', default=os.environ.get('FXCM_API_TOKEN'))
    parser.add_argument('--symbols', nargs='+', choices=sorted(PAIRS), default=None)
    args = parser.parse_args()

    try:
        start = parse_date(args.from_date, 'HISTORY_FROM')
        end = parse_date(args.to_date, 'HISTORY_TO')
        download(args.token, start, end, args.symbols)
    except Exception as exc:
        print(f'FXCM download failed: {exc}', file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
