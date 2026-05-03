-- ================================================================
-- Load ML model predictions into Postgres
-- Run with:
--   docker exec -i sailgp-postgres psql -U sailgp -d sailgp < load_predictions.sql
-- ================================================================

-- Create predictions table (drop and recreate for easy re-runs)
DROP TABLE IF EXISTS sailgp_predictions;

CREATE TABLE sailgp_predictions (
    id              SERIAL PRIMARY KEY,
    season          VARCHAR(20)  NOT NULL DEFAULT '2025-26',
    season_num      INT          NOT NULL DEFAULT 6,
    model           VARCHAR(50)  NOT NULL,  -- e.g. 'regression', 'classification'
    team            VARCHAR(50)  NOT NULL,
    avg_predicted_finish  NUMERIC(6,4),
    predicted_rank  INT,
    created_at      TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX idx_predictions_season ON sailgp_predictions(season_num);
CREATE INDEX idx_predictions_team   ON sailgp_predictions(team);

-- ----------------------------------------------------------------
-- Season 6 regression predictions
-- (from predict.py --target finish, trained on Seasons 1-5)
-- ----------------------------------------------------------------
INSERT INTO sailgp_predictions (season, season_num, model, team, avg_predicted_finish, predicted_rank) VALUES
    ('2025-26', 6, 'regression', 'Australia',    2.0442, 1),
    ('2025-26', 6, 'regression', 'Great Britain', 2.3570, 2),
    ('2025-26', 6, 'regression', 'Spain',         4.4791, 3),
    ('2025-26', 6, 'regression', 'Sweden',        4.5594, 4),
    ('2025-26', 6, 'regression', 'New Zealand',   5.3073, 5),
    ('2025-26', 6, 'regression', 'France',        5.7701, 6),
    ('2025-26', 6, 'regression', 'USA',           6.3112, 7),
    ('2025-26', 6, 'regression', 'Germany',       6.9945, 8),
    ('2025-26', 6, 'regression', 'Denmark',       7.2029, 9),
    ('2025-26', 6, 'regression', 'Italy',         8.4877, 10);

-- Verify
SELECT model, team, avg_predicted_finish, predicted_rank
FROM sailgp_predictions
ORDER BY model, predicted_rank;
