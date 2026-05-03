-- ================================================================
-- SailGP Metabase Dashboard Queries
-- Paste each block into a new SQL question in Metabase.
-- All queries target the `sailgp` database.
-- ================================================================


-- ----------------------------------------------------------------
-- 1. ALL-TIME EVENT WINS BY TEAM
--    Chart type: Bar chart (team on X, wins on Y)
-- ----------------------------------------------------------------
SELECT
    team,
    COUNT(*) AS event_wins
FROM sailgp_event_results
WHERE is_event_winner = TRUE
GROUP BY team
ORDER BY event_wins DESC;


-- ----------------------------------------------------------------
-- 2. EVENT WINS BY TEAM PER SEASON
--    Chart type: Grouped bar or stacked bar (season = series)
-- ----------------------------------------------------------------
SELECT
    season,
    team,
    COUNT(*) AS event_wins
FROM sailgp_event_results
WHERE is_event_winner = TRUE
GROUP BY season, team
ORDER BY season, event_wins DESC;


-- ----------------------------------------------------------------
-- 3. SEASON CHAMPIONSHIP RESULTS
--    Chart type: Table
-- ----------------------------------------------------------------
SELECT
    season,
    season_finish        AS championship_position,
    team,
    skipper,
    season_points        AS points,
    season_champion
FROM sailgp_season_standings
ORDER BY season, season_finish;


-- ----------------------------------------------------------------
-- 4. AVERAGE FINISH POSITION BY TEAM (ALL TIME)
--    Lower = better. Chart type: Bar chart
-- ----------------------------------------------------------------
SELECT
    team,
    ROUND(AVG(finish_position), 2)  AS avg_finish,
    COUNT(*)                         AS races_entered,
    MIN(finish_position)             AS best_finish,
    MAX(finish_position)             AS worst_finish
FROM sailgp_event_results
GROUP BY team
ORDER BY avg_finish ASC;


-- ----------------------------------------------------------------
-- 5. TEAM CONSISTENCY (STANDARD DEVIATION OF FINISH POSITION)
--    Lower stddev = more consistent. Chart type: Bar chart
-- ----------------------------------------------------------------
SELECT
    team,
    ROUND(STDDEV(finish_position)::NUMERIC, 2) AS finish_stddev,
    ROUND(AVG(finish_position)::NUMERIC, 2)    AS avg_finish,
    COUNT(*)                                    AS events_entered
FROM sailgp_event_results
GROUP BY team
HAVING COUNT(*) >= 5
ORDER BY finish_stddev ASC;


-- ----------------------------------------------------------------
-- 6. HOME VENUE ADVANTAGE
--    Compares a team's avg finish at home vs. away events.
--    Chart type: Table or side-by-side bar
-- ----------------------------------------------------------------
WITH team_country AS (
    -- Map team name to its country
    SELECT DISTINCT
        er.team,
        e.country AS event_country,
        er.finish_position,
        CASE WHEN er.team = e.event_winner AND er.team = e.country THEN TRUE
             WHEN e.country ILIKE '%' || er.team || '%'             THEN TRUE
             ELSE FALSE
        END AS is_home
    FROM sailgp_event_results er
    JOIN sailgp_events e ON er.event_id = e.event_id
),
home_map(team, home_country) AS (
    VALUES
        ('Australia',    'Australia'),
        ('Great Britain','Great Britain'),
        ('New Zealand',  'New Zealand'),
        ('France',       'France'),
        ('USA',          'USA'),
        ('Japan',        'Japan'),
        ('China',        'China'),
        ('Spain',        'Spain'),
        ('Denmark',      'Denmark'),
        ('Canada',       'Canada'),
        ('Germany',      'Germany'),
        ('Switzerland',  'Switzerland')
)
SELECT
    er.team,
    ROUND(AVG(CASE WHEN e.country = hm.home_country THEN er.finish_position END)::NUMERIC, 2) AS avg_home_finish,
    ROUND(AVG(CASE WHEN e.country != hm.home_country THEN er.finish_position END)::NUMERIC, 2) AS avg_away_finish,
    ROUND(AVG(CASE WHEN e.country != hm.home_country THEN er.finish_position END)::NUMERIC, 2)
        - ROUND(AVG(CASE WHEN e.country = hm.home_country THEN er.finish_position END)::NUMERIC, 2)
        AS home_advantage   -- positive = better at home
FROM sailgp_event_results er
JOIN sailgp_events e ON er.event_id = e.event_id
JOIN home_map hm ON er.team = hm.team
GROUP BY er.team
HAVING COUNT(CASE WHEN e.country = hm.home_country THEN 1 END) > 0
ORDER BY home_advantage DESC;


-- ----------------------------------------------------------------
-- 7. PERFORMANCE TREND OVER TIME (avg finish per season per team)
--    Chart type: Line chart (season on X, avg_finish on Y, team = series)
-- ----------------------------------------------------------------
SELECT
    er.season,
    er.season_num,
    er.team,
    ROUND(AVG(er.finish_position)::NUMERIC, 2) AS avg_finish_position,
    COUNT(*) AS events
FROM sailgp_event_results er
GROUP BY er.season, er.season_num, er.team
ORDER BY er.season_num, er.team;


-- ----------------------------------------------------------------
-- 8. EVENTS HOSTED BY COUNTRY
--    Chart type: Bar or map chart
-- ----------------------------------------------------------------
SELECT
    country,
    COUNT(*) AS events_hosted,
    COUNT(DISTINCT season) AS seasons_appeared
FROM sailgp_events
GROUP BY country
ORDER BY events_hosted DESC;


-- ----------------------------------------------------------------
-- 9. HEAD-TO-HEAD: HOW OFTEN DOES TEAM A FINISH AHEAD OF TEAM B?
--    Edit the two team names to compare any pair.
--    Chart type: Scalar / KPI card
-- ----------------------------------------------------------------
WITH matchup AS (
    SELECT
        a.event_id,
        a.finish_position AS team_a_pos,
        b.finish_position AS team_b_pos
    FROM sailgp_event_results a
    JOIN sailgp_event_results b
        ON a.event_id = b.event_id
       AND a.team = 'Australia'      -- ← change Team A here
       AND b.team = 'New Zealand'    -- ← change Team B here
)
SELECT
    'Australia vs New Zealand'       AS matchup,
    COUNT(*)                         AS events_together,
    SUM(CASE WHEN team_a_pos < team_b_pos THEN 1 ELSE 0 END) AS australia_ahead,
    SUM(CASE WHEN team_b_pos < team_a_pos THEN 1 ELSE 0 END) AS new_zealand_ahead,
    ROUND(100.0 * SUM(CASE WHEN team_a_pos < team_b_pos THEN 1 ELSE 0 END) / COUNT(*), 1) AS australia_win_pct
FROM matchup;


-- ----------------------------------------------------------------
-- 10. PODIUM RATE BY TEAM (% of events finishing top 3)
--     Chart type: Bar chart
-- ----------------------------------------------------------------
SELECT
    team,
    COUNT(*)                                                   AS total_events,
    SUM(CASE WHEN finish_position <= 3 THEN 1 ELSE 0 END)     AS podiums,
    ROUND(100.0 * SUM(CASE WHEN finish_position <= 3 THEN 1 ELSE 0 END) / COUNT(*), 1) AS podium_pct
FROM sailgp_event_results
GROUP BY team
ORDER BY podium_pct DESC;


-- ----------------------------------------------------------------
-- 11. POINTS-BASED SEASON PREDICTION (simple projection)
--    Uses avg event wins as a proxy for future performance.
--    Chart type: Table
-- ----------------------------------------------------------------
WITH recent_form AS (
    SELECT
        team,
        COUNT(*) FILTER (WHERE season_num >= 3) AS recent_events,
        SUM(CASE WHEN is_event_winner AND season_num >= 3 THEN 1 ELSE 0 END) AS recent_wins,
        ROUND(AVG(finish_position) FILTER (WHERE season_num >= 3)::NUMERIC, 2) AS recent_avg_finish
    FROM sailgp_event_results
    GROUP BY team
)
SELECT
    team,
    recent_events,
    recent_wins,
    recent_avg_finish,
    ROUND(100.0 * recent_wins / NULLIF(recent_events, 0), 1) AS win_rate_pct,
    RANK() OVER (ORDER BY recent_avg_finish ASC) AS predicted_rank
FROM recent_form
WHERE recent_events > 0
ORDER BY predicted_rank;


-- ----------------------------------------------------------------
-- 12. WIND SPEED VS FINISH POSITION (scatter plot data)
--     One row per team per event with wind conditions.
--     Chart type: Scatter plot — X: avg_wind_kmh, Y: finish_position
--     Break out by team series to see individual team wind curves.
-- ----------------------------------------------------------------
WITH event_wind AS (
    SELECT
        event_id,
        ROUND(AVG(wind_speed_max_kmh)::NUMERIC, 1) AS avg_wind_kmh,
        ROUND(AVG(wind_gusts_max_kmh)::NUMERIC, 1)  AS avg_gusts_kmh
    FROM sailgp_weather
    GROUP BY event_id
)
SELECT
    er.team,
    er.season,
    e.location,
    e.date_start,
    ew.avg_wind_kmh,
    ew.avg_gusts_kmh,
    er.finish_position,
    er.is_event_winner
FROM sailgp_event_results er
JOIN sailgp_events e      ON er.event_id = e.event_id
JOIN event_wind ew        ON er.event_id = ew.event_id
WHERE ew.avg_wind_kmh IS NOT NULL
ORDER BY er.team, e.date_start;


-- ----------------------------------------------------------------
-- 13. PERFORMANCE BY WIND CONDITION BUCKET (grouped bar)
--     Breaks each team's avg finish into three wind bands.
--     Chart type: Grouped bar — team on X, wind bucket as series
--     Lower avg_finish = better performance in those conditions.
-- ----------------------------------------------------------------
WITH event_wind AS (
    SELECT
        event_id,
        AVG(wind_speed_max_kmh) AS avg_wind_kmh
    FROM sailgp_weather
    GROUP BY event_id
),
bucketed AS (
    SELECT
        er.team,
        CASE
            WHEN ew.avg_wind_kmh < 20 THEN '1. Light  (<20 km/h)'
            WHEN ew.avg_wind_kmh < 35 THEN '2. Medium (20–35 km/h)'
            ELSE                            '3. Heavy  (>35 km/h)'
        END                                                    AS wind_bucket,
        er.finish_position,
        er.is_event_winner
    FROM sailgp_event_results er
    JOIN event_wind ew ON er.event_id = ew.event_id
)
SELECT
    team,
    wind_bucket,
    COUNT(*)                                                        AS events,
    ROUND(AVG(finish_position)::NUMERIC, 2)                        AS avg_finish,
    SUM(CASE WHEN is_event_winner THEN 1 ELSE 0 END)               AS wins,
    ROUND(100.0 * SUM(CASE WHEN is_event_winner THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                           AS win_pct
FROM bucketed
GROUP BY team, wind_bucket
HAVING COUNT(*) >= 3
ORDER BY team, wind_bucket;


-- ----------------------------------------------------------------
-- 14. HEAVY AIR vs LIGHT AIR SPECIALISTS
--     Ranks teams by how much better (or worse) they are in
--     strong wind vs light wind. Positive = heavy air specialist.
--     Chart type: Bar chart sorted by heavy_air_advantage
-- ----------------------------------------------------------------
WITH event_wind AS (
    SELECT
        event_id,
        AVG(wind_speed_max_kmh) AS avg_wind_kmh
    FROM sailgp_weather
    GROUP BY event_id
)
SELECT
    er.team,
    COUNT(CASE WHEN ew.avg_wind_kmh >= 30 THEN 1 END)              AS heavy_air_events,
    ROUND(AVG(CASE WHEN ew.avg_wind_kmh >= 30
                   THEN er.finish_position END)::NUMERIC, 2)       AS avg_finish_heavy,
    COUNT(CASE WHEN ew.avg_wind_kmh < 20 THEN 1 END)               AS light_air_events,
    ROUND(AVG(CASE WHEN ew.avg_wind_kmh < 20
                   THEN er.finish_position END)::NUMERIC, 2)       AS avg_finish_light,
    -- Positive value = performs better in heavy air than light air
    ROUND(
        AVG(CASE WHEN ew.avg_wind_kmh < 20  THEN er.finish_position END)
      - AVG(CASE WHEN ew.avg_wind_kmh >= 30 THEN er.finish_position END),
    2)                                                             AS heavy_air_advantage
FROM sailgp_event_results er
JOIN event_wind ew ON er.event_id = ew.event_id
GROUP BY er.team
HAVING COUNT(CASE WHEN ew.avg_wind_kmh >= 30 THEN 1 END) >= 3
   AND COUNT(CASE WHEN ew.avg_wind_kmh < 20  THEN 1 END) >= 3
ORDER BY heavy_air_advantage DESC;


-- ----------------------------------------------------------------
-- 15. SEASON 6 PREDICTED CHAMPIONSHIP STANDINGS
--     Model: regression (avg predicted finish position, lower = better)
--     Chart type: Table or horizontal bar chart
-- ----------------------------------------------------------------
SELECT
    predicted_rank   AS rank,
    team,
    avg_predicted_finish AS predicted_avg_finish
FROM sailgp_predictions
WHERE season_num = 6
  AND model = 'regression'
ORDER BY predicted_rank;


-- ----------------------------------------------------------------
-- 16. PREDICTED vs ACTUAL: HOW IS THE MODEL TRACKING?
--     Compares model's predicted rank to actual avg finish so far
--     in Season 6. Only meaningful once >= 2 S6 events have run.
--     Chart type: Scatter (predicted_rank on X, actual_avg_finish on Y)
--     Teams near the diagonal = model is accurate for them.
-- ----------------------------------------------------------------
SELECT
    p.team,
    p.predicted_rank,
    p.avg_predicted_finish,
    ROUND(AVG(er.finish_position)::NUMERIC, 2) AS actual_avg_finish_s6,
    COUNT(er.event_id)                          AS s6_events_completed,
    RANK() OVER (ORDER BY AVG(er.finish_position) ASC) AS actual_rank_s6
FROM sailgp_predictions p
LEFT JOIN sailgp_event_results er
    ON p.team = er.team
   AND er.season_num = 6
WHERE p.season_num = 6
  AND p.model = 'regression'
GROUP BY p.team, p.predicted_rank, p.avg_predicted_finish
ORDER BY p.predicted_rank;


-- ----------------------------------------------------------------
-- 17. MODEL ACCURACY SUMMARY
--     Shows rank delta (predicted vs actual) per team.
--     Positive delta = model ranked them higher than reality.
--     Chart type: Bar chart sorted by rank_delta
-- ----------------------------------------------------------------
WITH actuals AS (
    SELECT
        team,
        ROUND(AVG(finish_position)::NUMERIC, 2) AS actual_avg_finish,
        RANK() OVER (ORDER BY AVG(finish_position) ASC) AS actual_rank
    FROM sailgp_event_results
    WHERE season_num = 6
    GROUP BY team
)
SELECT
    p.team,
    p.predicted_rank,
    a.actual_rank,
    (p.predicted_rank - a.actual_rank::INT) AS rank_delta,
    p.avg_predicted_finish,
    a.actual_avg_finish
FROM sailgp_predictions p
JOIN actuals a ON p.team = a.team
WHERE p.season_num = 6
  AND p.model = 'regression'
ORDER BY ABS(p.predicted_rank - a.actual_rank::INT) ASC;
