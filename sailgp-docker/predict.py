#!/usr/bin/env python3
"""
predict.py
Builds and compares ML models to predict SailGP event winners and season
championship positions. Uses performance history + weather features.

Usage:
  python predict.py                  # full report + Season 6 predictions
  python predict.py --target winner  # predict event winner (classification)
  python predict.py --target finish  # predict finish position (regression)

Output:
  - Model comparison table (accuracy / MAE per model)
  - Feature importance rankings
  - Season 6 championship predictions printed to console
  - Results saved to: predictions_season6.csv
"""

import argparse
import warnings
warnings.filterwarnings("ignore")

import pandas as pd
import numpy as np
import psycopg2
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor, GradientBoostingClassifier, GradientBoostingRegressor
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import cross_val_score, LeaveOneGroupOut
from sklearn.pipeline import Pipeline
from sklearn.metrics import accuracy_score, mean_absolute_error

# ── Postgres connection ────────────────────────────────────────────────────────
DB = dict(host="localhost", port=5432, dbname="sailgp", user="sailgp", password="sailgp_pass")

def load_data(conn) -> pd.DataFrame:
    """Load event results joined with weather data."""
    query = """
        SELECT
            er.event_id,
            er.season,
            er.season_num,
            er.team,
            er.finish_position,
            er.is_event_winner,
            e.location,
            e.country,
            e.date_start,
            -- Weather: average across race days (may be NULL if not yet fetched)
            AVG(w.wind_speed_max_kmh)          AS wind_speed_avg,
            AVG(w.wind_gusts_max_kmh)          AS wind_gusts_avg,
            AVG(w.wind_direction_dominant_deg) AS wind_dir_avg,
            AVG(w.precipitation_mm)            AS precip_avg
        FROM sailgp_event_results er
        JOIN sailgp_events e ON er.event_id = e.event_id
        LEFT JOIN sailgp_weather w ON w.event_id = er.event_id
        GROUP BY er.event_id, er.season, er.season_num, er.team,
                 er.finish_position, er.is_event_winner,
                 e.location, e.country, e.date_start
        ORDER BY e.date_start, er.finish_position
    """
    return pd.read_sql(query, conn)

def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Engineer features for each (team, event) row.
    We use only information available BEFORE the event to avoid leakage.
    """
    df = df.sort_values(["team", "date_start"]).copy()
    df["date_start"] = pd.to_datetime(df["date_start"])

    rows = []
    for team, grp in df.groupby("team"):
        grp = grp.sort_values("date_start").reset_index(drop=True)
        for i, row in grp.iterrows():
            past = grp[grp["date_start"] < row["date_start"]]

            # ── Performance features ───────────────────────────────────────
            n_past = len(past)
            avg_finish_all    = past["finish_position"].mean()   if n_past > 0 else None
            avg_finish_last3  = past.tail(3)["finish_position"].mean() if n_past > 0 else None
            avg_finish_last6  = past.tail(6)["finish_position"].mean() if n_past > 0 else None
            win_rate          = past["is_event_winner"].mean()   if n_past > 0 else None
            podium_rate       = (past["finish_position"] <= 3).mean() if n_past > 0 else None
            finish_stddev     = past["finish_position"].std()    if n_past > 1 else None
            last_finish       = past.iloc[-1]["finish_position"] if n_past > 0 else None
            events_since_win  = (
                (i - past[past["is_event_winner"]].index.max())
                if n_past > 0 and past["is_event_winner"].any() else n_past
            )

            # ── Venue familiarity ──────────────────────────────────────────
            past_at_venue   = past[past["location"] == row["location"]]
            avg_finish_venue = past_at_venue["finish_position"].mean() if len(past_at_venue) > 0 else None

            # ── Home country ───────────────────────────────────────────────
            home_map = {
                "Australia": "Australia", "Great Britain": "Great Britain",
                "New Zealand": "New Zealand", "France": "France",
                "USA": "USA", "Japan": "Japan", "China": "China",
                "Spain": "Spain", "Denmark": "Denmark", "Canada": "Canada",
                "Germany": "Germany", "Switzerland": "Switzerland",
                "Sweden": "Sweden", "Italy": "Italy",
            }
            is_home = int(home_map.get(team, "") == row["country"])

            rows.append({
                # Identifiers (not used as features)
                "event_id":           row["event_id"],
                "season":             row["season"],
                "season_num":         row["season_num"],
                "team":               team,
                "date_start":         row["date_start"],
                # Target variables
                "finish_position":    row["finish_position"],
                "is_event_winner":    int(row["is_event_winner"]),
                # Features
                "n_events":           n_past,
                "avg_finish_all":     avg_finish_all,
                "avg_finish_last3":   avg_finish_last3,
                "avg_finish_last6":   avg_finish_last6,
                "win_rate":           win_rate,
                "podium_rate":        podium_rate,
                "finish_stddev":      finish_stddev,
                "last_finish":        last_finish,
                "events_since_win":   events_since_win,
                "avg_finish_venue":   avg_finish_venue,
                "is_home":            is_home,
                # Weather
                "wind_speed_avg":     row["wind_speed_avg"],
                "wind_gusts_avg":     row["wind_gusts_avg"],
                "wind_dir_avg":       row["wind_dir_avg"],
                "precip_avg":         row["precip_avg"],
            })

    return pd.DataFrame(rows)

FEATURE_COLS = [
    "n_events", "avg_finish_all", "avg_finish_last3", "avg_finish_last6",
    "win_rate", "podium_rate", "finish_stddev", "last_finish",
    "events_since_win", "avg_finish_venue", "is_home",
    "wind_speed_avg", "wind_gusts_avg", "wind_dir_avg", "precip_avg",
]

def prepare_Xy(feat: pd.DataFrame, target: str, min_past_events: int = 3):
    """Return X, y, groups (season_num) for cross-validation, dropping rows with insufficient history."""
    df = feat[feat["n_events"] >= min_past_events].copy()
    df[FEATURE_COLS] = df[FEATURE_COLS].fillna(df[FEATURE_COLS].median())

    X = df[FEATURE_COLS].values
    y = df[target].values
    groups = df["season_num"].values
    meta  = df[["event_id", "season", "team", "date_start"]].copy()
    return X, y, groups, meta

def compare_models(X, y, groups, task: str):
    """
    Cross-validate multiple models using Leave-One-Season-Out strategy.
    Each fold holds out one full season as the test set.
    """
    logo = LeaveOneGroupOut()

    if task == "classification":
        models = {
            "Logistic Regression":   Pipeline([("scaler", StandardScaler()), ("clf", LogisticRegression(max_iter=1000))]),
            "Random Forest":         RandomForestClassifier(n_estimators=200, random_state=42),
            "Gradient Boosting":     GradientBoostingClassifier(n_estimators=200, random_state=42),
        }
        scoring = "accuracy"
    else:
        models = {
            "Ridge Regression":      Pipeline([("scaler", StandardScaler()), ("reg", Ridge())]),
            "Random Forest":         RandomForestRegressor(n_estimators=200, random_state=42),
            "Gradient Boosting":     GradientBoostingRegressor(n_estimators=200, random_state=42),
        }
        scoring = "neg_mean_absolute_error"

    results = {}
    for name, model in models.items():
        scores = cross_val_score(model, X, y, cv=logo, groups=groups, scoring=scoring)
        if task == "classification":
            results[name] = {"mean": scores.mean(), "std": scores.std(), "metric": "Accuracy"}
        else:
            results[name] = {"mean": -scores.mean(), "std": scores.std(), "metric": "MAE (positions)"}
        print(f"  {name:28s}  {results[name]['metric']}: {results[name]['mean']:.3f} ± {results[name]['std']:.3f}")

    best = min(results, key=lambda k: results[k]["mean"] if task == "regression" else -results[k]["mean"])
    return best, models[best]

def get_feature_importances(model, feature_names):
    """Extract feature importances from tree-based or linear models."""
    if hasattr(model, "feature_importances_"):
        imp = model.feature_importances_
    elif hasattr(model, "named_steps"):
        clf = list(model.named_steps.values())[-1]
        if hasattr(clf, "coef_"):
            imp = np.abs(clf.coef_[0]) if clf.coef_.ndim > 1 else np.abs(clf.coef_)
        else:
            return {}
    else:
        return {}
    return dict(sorted(zip(feature_names, imp), key=lambda x: -x[1]))

def predict_season6(model, feat: pd.DataFrame, X_train, y_train):
    """Predict Season 6 outcomes using model trained on all prior seasons."""
    model.fit(X_train, y_train)

    s6 = feat[feat["season"] == "2026"].copy()
    if s6.empty:
        print("\n  No Season 6 rows with sufficient history to predict.")
        return pd.DataFrame()

    s6[FEATURE_COLS] = s6[FEATURE_COLS].fillna(feat[FEATURE_COLS].median())
    X6 = s6[FEATURE_COLS].values

    if hasattr(model, "predict_proba"):
        proba = model.predict_proba(X6)
        win_col = list(model.classes_).index(1) if hasattr(model, "classes_") else 1
        s6["win_probability"] = proba[:, win_col]
    else:
        s6["predicted_finish"] = model.predict(X6)

    return s6

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=["winner", "finish"], default="winner")
    args = parser.parse_args()

    task   = "classification" if args.target == "winner" else "regression"
    target = "is_event_winner" if task == "classification" else "finish_position"

    conn = psycopg2.connect(**DB)
    print("Loading data from Postgres...")
    raw  = load_data(conn)
    conn.close()

    print(f"  {len(raw)} rows across {raw['season'].nunique()} seasons, {raw['team'].nunique()} teams")

    print("\nEngineering features...")
    feat = build_features(raw)
    print(f"  {len(feat)} feature rows built")

    X, y, groups, meta = prepare_Xy(feat, target)
    print(f"  {len(X)} rows usable (≥3 prior events for context)")

    print(f"\nComparing models — Leave-One-Season-Out CV ({task}):")
    best_name, best_model = compare_models(X, y, groups, task)
    print(f"\n  ✅ Best model: {best_name}")

    print("\nFeature importances (best model, trained on all data):")
    best_model.fit(X, y)
    importances = get_feature_importances(best_model, FEATURE_COLS)
    for feat_name, imp in list(importances.items())[:10]:
        bar = "█" * int(imp * 100 / max(importances.values()) * 20)
        print(f"  {feat_name:28s} {bar} {imp:.4f}")

    print("\nSeason 6 predictions:")
    X_train = feat[feat["season"] != "2026"][FEATURE_COLS].fillna(feat[FEATURE_COLS].median()).values
    y_train = feat[feat["season"] != "2026"][target].values

    preds = predict_season6(best_model, feat, X_train, y_train)

    if not preds.empty:
        if "win_probability" in preds.columns:
            # Aggregate per team: average win probability across S6 events
            summary = (
                preds.groupby("team")["win_probability"]
                .mean()
                .sort_values(ascending=False)
                .reset_index()
            )
            summary.columns = ["team", "avg_win_probability"]
            summary["predicted_rank"] = range(1, len(summary) + 1)
            print(summary.to_string(index=False))
            summary.to_csv("predictions_season6.csv", index=False)
        else:
            summary = (
                preds.groupby("team")["predicted_finish"]
                .mean()
                .sort_values()
                .reset_index()
            )
            summary.columns = ["team", "avg_predicted_finish"]
            summary["predicted_rank"] = range(1, len(summary) + 1)
            print(summary.to_string(index=False))
            summary.to_csv("predictions_season6.csv", index=False)

        print("\nPredictions saved to predictions_season6.csv")

if __name__ == "__main__":
    main()
