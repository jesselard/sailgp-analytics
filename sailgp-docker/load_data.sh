#!/bin/bash
# load_data.sh — copies SailGP CSVs into the Postgres container and loads them.
# Run this from the sailgp-docker/ directory AFTER docker compose up.
#
# Usage:
#   chmod +x load_data.sh
#   ./load_data.sh

set -e

CONTAINER="sailgp-postgres"
DB="sailgp"
USER="sailgp"
CSV_DIR="$(cd "$(dirname "$0")/.." && pwd)"  # parent folder = outputs/

echo "⏳ Waiting for Postgres to be ready..."
until docker exec "$CONTAINER" pg_isready -U "$USER" -d "$DB" -q; do
  sleep 1
done
echo "✅ Postgres is ready."

echo ""
echo "📂 Copying CSV files into container..."
docker cp "$CSV_DIR/sailgp_events.csv"          "$CONTAINER:/tmp/sailgp_events.csv"
docker cp "$CSV_DIR/sailgp_event_results.csv"   "$CONTAINER:/tmp/sailgp_event_results.csv"
docker cp "$CSV_DIR/sailgp_season_standings.csv" "$CONTAINER:/tmp/sailgp_season_standings.csv"
echo "✅ Files copied."

echo ""
echo "📥 Loading sailgp_events..."
docker exec "$CONTAINER" psql -U "$USER" -d "$DB" -c \
  "COPY sailgp_events(event_id,season,season_num,event_name,location,country,date_start,date_end,event_winner)
   FROM '/tmp/sailgp_events.csv' CSV HEADER;"

echo "📥 Loading sailgp_event_results..."
docker exec "$CONTAINER" psql -U "$USER" -d "$DB" -c \
  "COPY sailgp_event_results(event_id,season,season_num,event_name,location,country,team,finish_position,is_event_winner,notes)
   FROM '/tmp/sailgp_event_results.csv' CSV HEADER;"

echo "📥 Loading sailgp_season_standings..."
docker exec "$CONTAINER" psql -U "$USER" -d "$DB" -c \
  "COPY sailgp_season_standings(season,season_num,team,skipper,season_finish,season_points,season_champion)
   FROM '/tmp/sailgp_season_standings.csv' CSV HEADER;"

echo ""
echo "🎉 All data loaded! Quick row counts:"
docker exec "$CONTAINER" psql -U "$USER" -d "$DB" -c \
  "SELECT 'sailgp_events' AS table_name, COUNT(*) AS rows FROM sailgp_events
   UNION ALL
   SELECT 'sailgp_event_results', COUNT(*) FROM sailgp_event_results
   UNION ALL
   SELECT 'sailgp_season_standings', COUNT(*) FROM sailgp_season_standings;"
