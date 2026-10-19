"""Работа со временем среза."""

import pandas as pd

from northcart.const import DATA_TZ


def to_T(run_date: str) -> pd.Timestamp:
    """'YYYY-MM-DD' → полночь в DATA_TZ. Правая граница всех окон, не включается."""
    return pd.Timestamp(run_date, tz=DATA_TZ).normalize()


def to_db(ts: pd.Timestamp):
    """UTC → naive datetime для сравнения с timestamp без time zone."""
    return ts.tz_convert("UTC").tz_localize(None).to_pydatetime()
