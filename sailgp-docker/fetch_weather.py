#!/usr/bin/env python3
"""
fetch_weather.py
Fetches historical weather for every SailGP event from the free Open-Meteo
archive API and stores it in a sailgp_weather table in Postgres.

Usage:
  python fetch_weather.py          # fetch weather for all events
  python fetch_weather.py --season 2026   # one season only

API docs: https://open-meteo.com/en/docs/historical-weather-api
"""

import argparse
import time

import psycopg2
import requests

# ── Postgres connection ────────────────────────────────────────────────────────
DB = dict(host="localhost", port=5432, dbname="sailgp", user="sailgp", password="sailgp_pass")

# ── Venue coordinates (lat, lon) ───────────────────────────────────────────────
VENUE_COORDS = {
    "Sydney":          (-33.87,   151.21),
    "San Francisco":   ( 37.81,  -122.48),
    "New York":        ( 40.69,   -74.04),
    "Cowes":           ( 50.75,    -1.30),
    "Marseille":       ( 43.30,     5.37),
    "Bermuda":         ( 32.31,   -64.75),
    "Taranto":         ( 40.46,    17.25),
    "Plymouth":        ( 50.37,    -4.14),
    "Aarhus":          ( 56.16,    10.20),
    "Saint-Tropez":    ( 43.27,     6.64),
    "Cadiz":           ( 36.53,    -6.29),
    "Dubai":           ( 25.07,    55.17),
    "Auckland":        (-36.85,   174.76),
    "Christchurch":    (-43.53,   172.64),
    "Chicago":         ( 41.89,   -87.61),
    "Los Angeles":     ( 33.94,  -118.41),
    "Halifax":         ( 44.65,   -63.58),
    "Perth":           (-31.95,   115.86),
    "Abu Dhabi":       ( 24.45,    54.38),
    "Portsmouth":      ( 50.80,    -1.09),
    "Sassnitz":        ( 54.52,    13.64),
    "Geneva":          ( 46.20,     6.14),
    "Rio de Janeiro":  (-22.91,   -43.17),
    "Singapore":       (  1.29,   103.86),
    "Hamilton Island": (-20.35,   148.95),
}

# ── Open-Meteo variables ───────────────────────────────────────────────────────
DAILY_VARS = [
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
    "wind_direction_10m_dominant",
    "precipitation_sum",
    "temperature_2m_max",
    "temperature_2m_min",
]

SCHEMA = """
CREATE TABLE IF NOT EXISTS sailgp_weather (
    id                          SERIAL PRIMARY KEY,
    event_id                    VARCHAR(10) REFERENCES sailgp_events(event_id),
    location                    VARCHAR(100),
    date                        DATE,
    wind_speed_max_kmh          NUMERIC(6,2),
    wind_gusts_max_kmh          NUMERIC(6,2),
    wind_direction_dominant_deg NUMERIC(6,1),
    precipitation_mm            NUMERIC(6,2),
    temp_max_c                  NUMERIC(5,2),
    temp_min_c                  NUMERIC(5,2),
    UNIQUE(event_id, date)
);
"""

def fetch_weather(lat: float, lon: float, start: str, end: str) -> list[dict]:
    url = "https://archive-api.open-meteo.com/v1/archive"
    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start,
        "end_date": end,
        "daily": ",".join(DAILY_VARS),
        "timezone": "auto",
        "wind_speed_unit": "kmh",
    }
    resp = requests.get(url, params=params, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    daily = data.get("daily", {})
    dates = daily.get("time", [])
    rows = []
    for i, date in enumerate(dates):
        rows.append({
            "date":           date,
            "wind_speed_max": daily.get("wind_speed_10m_max",          [None])[i],
            "wind_gusts_max": daily.get("wind_gusts_10m_max",          [None])[i],
            "wind_dir":       daily.get("wind_direction_10m_dominant",  [None])[i],
            "precip":         daily.get("precipitation_sum",            [None])[i],
            "temp_max":       daily.get("temperature_2m_max",           [None])[i],
            "temp_min":       daily.get("temperature_2m_min",           [None])[i],
        })
    return rows

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--season", default=None, help="Limit to one season (e.g. 2026)")
    args = parser.parse_args()

    conn = psycopg2.connect(**DB)
    cur = conn.cursor()

    # Create weather table
    cur.execute(SCHEMA)
    conn.commit()

    # Fetch all events
    query = "SELECT event_id, location, date_start, date_end FROM sailgp_events WHERE date_start IS NOT NULL"
    params = []
    if args.season:
        query += " AND season = %s"
        params.append(args.season)
    query += " ORDER BY date_start"

    cur.execute(query, params)
    events = cur.fetchall()
    print(f"Fetching weather for {len(events)} events...\n")

    for event_id, location, date_start, date_end in events:
        coords = VENUE_COORDS.get(location)
        if not coords:
            print(f"  ⚠️  No coordinates for '{location}' — skipping {event_id}")
            continue

        lat, lon = coords
        start_str = str(date_start)
        end_str   = str(date_end)

        try:
            rows = fetch_weather(lat, lon, start_str, end_str)
            for row in rows:
                cur.execute("""
                    INSERT INTO sailgp_weather
                        (event_id, location, date,
                         wind_speed_max_kmh, wind_gusts_max_kmh,
                         wind_direction_dominant_deg, precipitation_mm,
                         temp_max_c, temp_min_c)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (event_id, date) DO UPDATE SET
                        wind_speed_max_kmh          = EXCLUDED.wind_speed_max_kmh,
                        wind_gusts_max_kmh          = EXCLUDED.wind_gusts_max_kmh,
                        wind_direction_dominant_deg = EXCLUDED.wind_direction_dominant_deg,
                        precipitation_mm            = EXCLUDED.precipitation_mm,
                        temp_max_c                  = EXCLUDED.temp_max_c,
                        temp_min_c                  = EXCLUDED.temp_min_c
                """, (event_id, location, row["date"],
                      row["wind_speed_max"], row["wind_gusts_max"],
                      row["wind_dir"], row["precip"],
                      row["temp_max"], row["temp_min"]))
            conn.commit()
            print(f"  ✅ {event_id} ({location} {start_str}): {len(rows)} day(s) fetched")
        except Exception as e:
            print(f"  ❌ {event_id} ({location}): {e}")

        time.sleep(0.5)  # be polite to the free API

    cur.close()
    conn.close()

    print("\nWeather fetch complete.")
    print("Preview in Metabase with: SELECT * FROM sailgp_weather ORDER BY date LIMIT 20;")

if __name__ == "__main__":
    main()
