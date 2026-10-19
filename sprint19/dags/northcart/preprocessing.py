"""Предобработка: удаление строк с NULL в ключах и дублей событий."""

import logging
from dataclasses import fields

import pandas as pd

from northcart.scheme import NorthCartTables, Table

log = logging.getLogger(__name__)

KEYS = {
    "customers": ["customer_id"],
    "orders": ["order_id", "customer_id"],
    "last_purchase": ["customer_id"],
    "sessions": ["session_id", "customer_id"],
    "events": ["session_id", "customer_id"],
}


def drop_null_keys(t: Table) -> None:
    cols = KEYS[t.name]
    mask = t.df[cols].isna().any(axis=1)
    if mask.any():
        log.warning("%s: удалено строк с NULL в %s: %d", t.name, cols, int(mask.sum()))
        t.df = t.df[~mask]


def dedup_events(df: pd.DataFrame) -> pd.DataFrame:
    before = len(df)
    null_id = df["event_id"].isna()  # в БД event_id int4 NULL
    deduped = df[~null_id].sort_values(["event_id", "timestamp"]).drop_duplicates(subset="event_id", keep="first")
    df = pd.concat([deduped, df[null_id]]).sort_index()
    removed = before - len(df)
    log.info("events: удалено дублей по event_id: %d (%.2f%%)", removed, 100 * removed / max(before, 1))

    body = ["session_id", "timestamp", "event_type", "product_id"]
    log.info("events: подозрительных повторов тела: %d", int(df.duplicated(subset=body).sum()))
    return df


def prepare_data(data: NorthCartTables) -> None:
    for f in fields(data):
        drop_null_keys(getattr(data, f.name))
    data.events.df = dedup_events(data.events.df)
