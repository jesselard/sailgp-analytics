# SailGP Analytics — Metabase AI Hackathon

A full analytics pipeline for SailGP racing — from raw results to ML predictions to a live Metabase dashboard queryable by Claude via the Metabase MCP server.

---

## What this is

SailGP is the world's fastest sail racing league, running since 2019. There's no public data API. This project builds one from scratch:

- **6 seasons of race results** compiled from Wikipedia and news sources (48 events, ~400 team-event rows)
- **Historical weather data** for every venue via the Open-Meteo archive API — wind speed, gusts, direction, precipitation for each race day
- **ML championship predictions** for Season 6 (currently in progress), trained on Seasons 1–5 using Ridge Regression with Leave-One-Season-Out cross-validation
- **17 Metabase dashboard queries** covering performance, consistency, home advantage, wind conditions, and model accuracy
- **Metabase MCP integration** — Claude can query the live dashboard in natural language

---

## The AI angle

Claude (via Anthropic's Cowork) designed the database schema, wrote the scraper, built the weather fetcher, engineered the ML features, and wrote every SQL query in this project. Then, via the **Metabase MCP server** (new in Metabase v0.60), Claude connects back to the live data and answers questions directly:

```
> Which team performs best in heavy winds, and does that match their Season 6 prediction?
> Australia is leading Season 6 — is that consistent with their historical record or a surprise?
> Who are the heavy air specialists vs light air specialists?
```

Claude built it. Claude can query it. The loop is closed.

---

## Stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL 16 (Docker) |
| Dashboard | Metabase v0.60 (Docker) |
| Scraper | Python + BeautifulSoup + pandas |
| Weather | Open-Meteo historical archive API |
| ML model | scikit-learn — Ridge Regression, Leave-One-Season-Out CV |
| AI integration | Metabase MCP server + Claude |

---

## Schema

```
sailgp_events          — 48 events, S1–S6 (location, country, dates, winner)
sailgp_event_results   — ~400 rows, one per team per event (finish position, is_event_winner)
sailgp_season_standings — season-level standings (points, champion, skipper)
sailgp_weather         — daily weather per event (wind, gusts, precipitation, temp)
sailgp_predictions     — ML model output (avg predicted finish, predicted rank per team)
```

---

## Running it yourself

**Prerequisites:** Docker Desktop, Python 3.9+, Metabase v0.60+

```bash
# 1. Start Postgres + Metabase
cd sailgp-docker
docker compose up -d

# 2. Load historical data (wait ~60s for containers to be ready)
chmod +x load_data.sh && ./load_data.sh

# 3. Insert Season 6 results
docker exec -i sailgp-postgres psql -U sailgp -d sailgp < insert_season6.sql

# 4. Fetch weather data for all venues (takes ~2 minutes)
pip install -r requirements.txt
python3 fetch_weather.py

# 5. Run ML predictions
python3 predict.py --target finish

# 6. Load predictions into Postgres
docker exec -i sailgp-postgres psql -U sailgp -d sailgp < load_predictions.sql

# 7. Open Metabase at http://localhost:3000
# Add Postgres connection: host=postgres, port=5432, db=sailgp, user=sailgp, pass=sailgp_pass
# Paste queries from dashboard_queries.sql into new SQL questions
```

**Connect Claude via MCP:**
```bash
claude mcp add metabase http://localhost:3000/api/mcp --transport http
cd sailgp-docker && claude
```

---

## Dashboard queries

`sailgp-docker/dashboard_queries.sql` contains 17 queries ready to paste into Metabase:

1. All-time event wins by team
2. Event wins by team per season
3. Season championship results
4. Average finish position by team
5. Team consistency (finish position standard deviation)
6. Home venue advantage
7. Performance trend over time (line chart)
8. Events hosted by country
9. Head-to-head comparison
10. Podium rate by team
11. Points-based season prediction
12. Wind speed vs finish position (scatter)
13. Performance by wind condition bucket
14. Heavy air vs light air specialists
15. Season 6 predicted standings (ML model)
16. Predicted vs actual tracking (scatter)
17. Model accuracy by team (rank delta)

---

## ML model notes

- **Algorithm:** Ridge Regression (best MAE in cross-validation: ~1.25 finish positions)
- **Validation:** Leave-One-Season-Out (trains on 5 seasons, predicts the 6th, rotates)
- **Features:** rolling avg finish (last 3, last 6 events), win rate, podium rate, finish consistency, home venue flag, venue-specific history, momentum (events since last win), weather (avg wind/gusts for venue)
- **Caveat:** Sweden and Italy are new in Season 6 with no historical data — their predictions rely on median imputation

**Season 6 predictions (as of 4 events):**

| Rank | Team | Predicted Avg Finish |
|---|---|---|
| 1 | Australia | 2.04 |
| 2 | Great Britain | 2.36 |
| 3 | Spain | 4.48 |
| 4 | Sweden | 4.56 |
| 5 | New Zealand | 5.31 |
| 6 | France | 5.77 |
| 7 | USA | 6.31 |
| 8 | Germany | 6.99 |
| 9 | Denmark | 7.20 |
| 10 | Italy | 8.49 |

---

## Keeping it current

After each SailGP event, run:
```bash
python3 scraper.py --season 2026   # pull new results from Wikipedia
python3 predict.py --target finish  # rerun model with updated data
docker exec -i sailgp-postgres psql -U sailgp -d sailgp < load_predictions.sql
```

Metabase queries update automatically on next load.

---

*Built with Claude (Anthropic Cowork) for the [Metabase AI Hackathon](https://www.metabase.com/blog/metabase-ai-hackathon)*
