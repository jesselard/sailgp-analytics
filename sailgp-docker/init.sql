-- SailGP Database Schema
-- Run automatically by Postgres on first container startup

-- ----------------------------------------------------------------
-- sailgp_events: one row per event (venue + season)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sailgp_events (
    event_id        VARCHAR(10)  PRIMARY KEY,
    season          VARCHAR(10)  NOT NULL,
    season_num      INTEGER      NOT NULL,
    event_name      VARCHAR(100) NOT NULL,
    location        VARCHAR(100),
    country         VARCHAR(50),
    date_start      DATE,
    date_end        DATE,
    event_winner    VARCHAR(50)
);

-- ----------------------------------------------------------------
-- sailgp_event_results: one row per team per event
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sailgp_event_results (
    id               SERIAL       PRIMARY KEY,
    event_id         VARCHAR(10)  NOT NULL REFERENCES sailgp_events(event_id),
    season           VARCHAR(10)  NOT NULL,
    season_num       INTEGER      NOT NULL,
    event_name       VARCHAR(100),
    location         VARCHAR(100),
    country          VARCHAR(50),
    team             VARCHAR(50)  NOT NULL,
    finish_position  INTEGER      NOT NULL,
    is_event_winner  BOOLEAN      DEFAULT FALSE,
    notes            TEXT
);

-- ----------------------------------------------------------------
-- sailgp_season_standings: one row per team per season
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sailgp_season_standings (
    id               SERIAL       PRIMARY KEY,
    season           VARCHAR(10)  NOT NULL,
    season_num       INTEGER      NOT NULL,
    team             VARCHAR(50)  NOT NULL,
    skipper          VARCHAR(100),
    season_finish    INTEGER,
    season_points    INTEGER,
    season_champion  BOOLEAN      DEFAULT FALSE
);

-- ----------------------------------------------------------------
-- Indexes for common query patterns
-- ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_results_team        ON sailgp_event_results(team);
CREATE INDEX IF NOT EXISTS idx_results_season      ON sailgp_event_results(season);
CREATE INDEX IF NOT EXISTS idx_results_event       ON sailgp_event_results(event_id);
CREATE INDEX IF NOT EXISTS idx_results_position    ON sailgp_event_results(finish_position);
CREATE INDEX IF NOT EXISTS idx_standings_team      ON sailgp_season_standings(team);
CREATE INDEX IF NOT EXISTS idx_standings_season    ON sailgp_season_standings(season);
CREATE INDEX IF NOT EXISTS idx_events_season       ON sailgp_events(season);
CREATE INDEX IF NOT EXISTS idx_events_country      ON sailgp_events(country);
