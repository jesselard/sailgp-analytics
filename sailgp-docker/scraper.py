#!/usr/bin/env python3
"""
sailgp_scraper.py
Scrapes the current SailGP season standings from Wikipedia and upserts
new event results into your local Postgres database.

Usage:
  python scraper.py                  # scrapes current season
  python scraper.py --season 2026    # scrapes a specific season

Schedule with cron (runs every Monday at 8am):
  0 8 * * 1 cd /path/to/sailgp-docker && python scraper.py >> scraper.log 2>&1
"""

import argparse
import re
import sys
from datetime import datetime

import pandas as pd
import psycopg2
import requests
from bs4 import BeautifulSoup

# ── Postgres connection ────────────────────────────────────────────────────────
DB = dict(host="localhost", port=5432, dbname="sailgp", user="sailgp", password="sailgp_pass")

# ── Wikipedia season URL mapping ───────────────────────────────────────────────
# Wikipedia uses different slug formats per season
SEASON_URLS = {
    "2019":    "2019_SailGP_championship",
    "2021-22": "2021%E2%80%9322_SailGP_championship",
    "2022-23": "2022%E2%80%9323_SailGP_championship",
    "2023-24": "2023%E2%80%9324_SailGP_championship",
    "2024-25": "2024%E2%80%9325_SailGP_championship",
    "2026":    "2026_SailGP_championship",
}

# ── Season metadata ────────────────────────────────────────────────────────────
SEASON_NUM = {
    "2019": 1, "2021-22": 2, "2022-23": 3,
    "2023-24": 4, "2024-25": 5, "2026": 6,
}

# ── Known event dates per season (extend as seasons progress) ─────────────────
# Format: {season: [(event_id, name, location, country, date_start, date_end), ...]}
EVENT_META = {
    "2026": [
        ("S6E1", "Oracle Perth Sail Grand Prix",    "Perth",          "Australia",  "2026-01-17", "2026-01-18"),
        ("S6E2", "ITM New Zealand Sail Grand Prix", "Auckland",       "New Zealand","2026-02-14", "2026-02-15"),
        ("S6E3", "KPMG Sydney Sail Grand Prix",     "Sydney",         "Australia",  "2026-02-28", "2026-03-01"),
        ("S6E4", "Enel Rio Sail Grand Prix",        "Rio de Janeiro", "Brazil",     "2026-04-11", "2026-04-12"),
        ("S6E5", "Apex Group Bermuda Sail Grand Prix", "Bermuda",     "Bermuda",    "2026-05-09", "2026-05-10"),
    ],
}

def fetch_wikipedia_page(slug: str) -> BeautifulSoup:
    url = f"https://en.wikipedia.org/wiki/{slug}"
    print(f"  Fetching {url}")
    resp = requests.get(url, headers={"User-Agent": "SailGP-Scraper/1.0"}, timeout=15)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "lxml")

def find_standings_table(soup: BeautifulSoup) -> pd.DataFrame | None:
    """
    Find the season standings table. Wikipedia SailGP pages have a table
    where rows = teams and columns = events (E1, E2 ...) + total points.
    """
    tables = pd.read_html(str(soup), flavor="lxml")
    for df in tables:
        cols = [str(c).lower() for c in df.columns]
        # Look for table that has team/nation column and event columns
        if any("team" in c or "nation" in c or "country" in c for c in cols):
            if sum(1 for c in cols if re.match(r"e\d|event|\d+", c)) >= 2:
                return df
    return None

def parse_finish(val) -> int | None:
    """Extract numeric finish position from a cell value like '1', '2*', 'DSQ', etc."""
    if pd.isna(val):
        return None
    s = str(val).strip()
    # Pull first number found
    m = re.search(r"\d+", s)
    return int(m.group()) if m else None

def upsert_event(cur, event_id: str, season: str, season_num: int,
                  name: str, location: str, country: str,
                  date_start: str, date_end: str, winner: str | None):
    cur.execute("""
        INSERT INTO sailgp_events
            (event_id, season, season_num, event_name, location, country, date_start, date_end, event_winner)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (event_id) DO UPDATE SET
            event_winner = EXCLUDED.event_winner
    """, (event_id, season, season_num, name, location, country, date_start, date_end, winner))

def upsert_result(cur, event_id: str, season: str, season_num: int,
                   event_name: str, location: str, country: str,
                   team: str, position: int, is_winner: bool, notes: str = ""):
    cur.execute("""
        INSERT INTO sailgp_event_results
            (event_id, season, season_num, event_name, location, country,
             team, finish_position, is_event_winner, notes)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT DO NOTHING
    """, (event_id, season, season_num, event_name, location, country,
          team, position, is_winner, notes))

def scrape_season(season: str):
    slug = SEASON_URLS.get(season)
    if not slug:
        print(f"No Wikipedia URL known for season {season}. Add it to SEASON_URLS.")
        sys.exit(1)

    season_num = SEASON_NUM[season]
    meta = EVENT_META.get(season, [])

    print(f"\nScraping Season {season_num} ({season})...")
    soup = fetch_wikipedia_page(slug)
    df = find_standings_table(soup)

    if df is None:
        print("  Could not find standings table — page structure may have changed.")
        sys.exit(1)

    print(f"  Found table with shape {df.shape}")
    print(f"  Columns: {list(df.columns)}")

    # Identify team column and event columns
    cols = list(df.columns)
    team_col = next((c for c in cols if re.search(r"team|nation|country", str(c), re.I)), cols[0])
    event_cols = [c for c in cols if re.match(r"E\d+|\d+", str(c), re.I)]

    if not event_cols:
        print("  Could not identify event columns. Check table structure manually.")
        sys.exit(1)

    conn = psycopg2.connect(**DB)
    cur = conn.cursor()
    inserted = 0

    for i, event_col in enumerate(event_cols):
        event_idx = i + 1
        event_id = f"S{season_num}E{event_idx}"

        # Look up metadata if available
        if i < len(meta):
            _, ename, location, country, dstart, dend = meta[i]
        else:
            ename = f"Event {event_idx}"
            location = "Unknown"
            country = "Unknown"
            dstart = dend = None

        # Parse team positions for this event
        results = []
        for _, row in df.iterrows():
            team = str(row[team_col]).strip()
            if not team or team.lower() in ("team", "nan", ""):
                continue
            pos = parse_finish(row[event_col])
            if pos is not None:
                results.append((team, pos))

        if not results:
            continue

        results.sort(key=lambda x: x[1])
        winner = results[0][0] if results else None

        upsert_event(cur, event_id, season, season_num,
                     ename, location, country, dstart, dend, winner)

        for team, pos in results:
            upsert_result(cur, event_id, season, season_num,
                          ename, location, country,
                          team, pos, pos == 1)
            inserted += 1

        print(f"  {event_id}: {ename} — winner: {winner} ({len(results)} teams)")

    conn.commit()
    cur.close()
    conn.close()
    print(f"\nDone. {inserted} result rows upserted.")

def main():
    parser = argparse.ArgumentParser(description="Scrape SailGP results from Wikipedia")
    parser.add_argument("--season", default="2026", help="Season to scrape (e.g. 2026)")
    args = parser.parse_args()
    scrape_season(args.season)

if __name__ == "__main__":
    main()
