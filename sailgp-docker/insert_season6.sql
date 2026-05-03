-- ================================================================
-- Season 6 (2026) Data Insert
-- Run with: docker exec sailgp-postgres psql -U sailgp -d sailgp -f /tmp/insert_season6.sql
-- ================================================================

-- ----------------------------------------------------------------
-- New teams in Season 6
-- ----------------------------------------------------------------
-- Australia   = BONDS Flying Roos       (Tom Slingsby)
-- Great Britain = Emirates GBR          (Dylan Fletcher)
-- New Zealand = Black Foils             (Peter Burling)
-- Spain       = Los Gallos              (Diego Botin)
-- USA         = U.S. SailGP Team        (Taylor Canfield)
-- France      = DS Automobiles Team     (Quentin Delapierre)
-- Denmark     = Rockwool Racing         (Nicolai Sehested)
-- Germany     = Germany Deutsche Bank   (Erik Heil)
-- Sweden      = Artemis SailGP          (Nathan Outteridge) -- NEW
-- Italy       = Red Bull Italy          (Francesco Bruni)   -- NEW

-- ----------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------
INSERT INTO sailgp_events (event_id, season, season_num, event_name, location, country, date_start, date_end, event_winner)
VALUES
  ('S6E1', '2026', 6, 'Oracle Perth Sail Grand Prix',    'Perth',          'Australia',  '2026-01-17', '2026-01-18', 'Great Britain'),
  ('S6E2', '2026', 6, 'ITM New Zealand Sail Grand Prix', 'Auckland',       'New Zealand','2026-02-14', '2026-02-15', 'Australia'),
  ('S6E3', '2026', 6, 'KPMG Sydney Sail Grand Prix',     'Sydney',         'Australia',  '2026-02-28', '2026-03-01', 'USA'),
  ('S6E4', '2026', 6, 'Enel Rio Sail Grand Prix',        'Rio de Janeiro', 'Brazil',     '2026-04-11', '2026-04-12', 'Australia')
ON CONFLICT (event_id) DO NOTHING;

-- ----------------------------------------------------------------
-- Event Results
-- ----------------------------------------------------------------

-- Event 1: Perth — GBR 1st, AUS 2nd, FRA 3rd, SWE 4th, USA 5th
-- Remaining positions estimated from standings/context
INSERT INTO sailgp_event_results (event_id, season, season_num, event_name, location, country, team, finish_position, is_event_winner, notes)
VALUES
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Great Britain', 1, TRUE,  'Season 6 opener win'),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Australia',     2, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','France',        3, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Sweden',        4, FALSE, 'Artemis — new team Season 6'),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','USA',           5, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Denmark',       6, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Spain',         7, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','New Zealand',   8, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Germany',       9, FALSE, ''),
  ('S6E1','2026',6,'Oracle Perth Sail Grand Prix','Perth','Australia','Italy',        10, FALSE, 'Red Bull Italy — new team Season 6')
ON CONFLICT DO NOTHING;

-- Event 2: Auckland — AUS 1st, GBR 2nd, ESP 3rd
-- NZ and France crashed out (DSQ/DNF), placed last
INSERT INTO sailgp_event_results (event_id, season, season_num, event_name, location, country, team, finish_position, is_event_winner, notes)
VALUES
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Australia',     1, TRUE,  'Dramatic win in squall conditions'),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Great Britain', 2, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Spain',         3, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Sweden',        4, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','USA',           5, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Denmark',       6, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Germany',       7, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','Italy',         8, FALSE, ''),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','New Zealand',   9, FALSE, 'DNF — collision on Day 1; crew hospitalised'),
  ('S6E2','2026',6,'ITM New Zealand Sail Grand Prix','Auckland','New Zealand','France',       10, FALSE, 'DNF — collision on Day 1; crew hospitalised')
ON CONFLICT DO NOTHING;

-- Event 3: Sydney — USA 1st, GBR 2nd, ESP 3rd
INSERT INTO sailgp_event_results (event_id, season, season_num, event_name, location, country, team, finish_position, is_event_winner, notes)
VALUES
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','USA',           1, TRUE,  ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Great Britain', 2, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Spain',         3, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Australia',     4, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Sweden',        5, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Denmark',       6, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','France',        7, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','New Zealand',   8, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Germany',       9, FALSE, ''),
  ('S6E3','2026',6,'KPMG Sydney Sail Grand Prix','Sydney','Australia','Italy',        10, FALSE, '')
ON CONFLICT DO NOTHING;

-- Event 4: Rio — AUS 1st, ESP 2nd, SWE 3rd, USA 4th, DEN 5th, GER 6th, ITA 7th, GBR last
INSERT INTO sailgp_event_results (event_id, season, season_num, event_name, location, country, team, finish_position, is_event_winner, notes)
VALUES
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Australia',     1, TRUE,  'Retakes series lead'),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Spain',         2, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Sweden',        3, FALSE, 'First event final for Artemis'),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','USA',           4, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Denmark',       5, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Germany',       6, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Italy',         7, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','France',        8, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','New Zealand',   9, FALSE, ''),
  ('S6E4','2026',6,'Enel Rio Sail Grand Prix','Rio de Janeiro','Brazil','Great Britain',10, FALSE, 'Last place — disastrous weekend')
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------
-- Verify
-- ----------------------------------------------------------------
SELECT season, COUNT(DISTINCT event_id) AS events, COUNT(*) AS result_rows
FROM sailgp_event_results
GROUP BY season ORDER BY season;
