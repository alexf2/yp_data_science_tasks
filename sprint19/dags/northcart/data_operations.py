"""Загрузка из Postgres только тех данных, которые нужны для среза run_date."""

import logging
import re
from dataclasses import fields

import pandas as pd
from sqlalchemy import text

from northcart.const import MAX_WINDOW
from northcart.scheme import NorthCartTables, Table
from northcart.utils import to_db, to_T

log = logging.getLogger(__name__)


def load_data(conn, schema_name: str, run_date: str) -> NorthCartTables:
    """Загружает таблицы за окно [T - MAX_WINDOW, T) и агрегат последней покупки."""
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", schema_name):
        raise ValueError(f"Недопустимое имя схемы: {schema_name!r}")

    T = to_T(run_date)
    params = {"t_start": to_db(T - pd.Timedelta(days=MAX_WINDOW)), "t_end": to_db(T)}
    log.info("Срез %s: окно загрузки [%s, %s) UTC", run_date, params["t_start"], params["t_end"])

    data = NorthCartTables()
    for f in fields(data):
        t: Table = getattr(data, f.name)
        sql = t.sql.format(schema=f'"{schema_name}"')
        used = {k: v for k, v in params.items() if f":{k}" in sql}
        t.df = pd.read_sql(text(sql), conn, params=used, dtype=t.dtype, parse_dates=t.parse_dates)
        t.postprocess()
        t.df.attrs["name"] = t.name
        log.info("✅ %s: %d строк x %d колонок", t.name, *t.df.shape)
    return data
