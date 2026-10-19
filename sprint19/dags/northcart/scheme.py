"""Схема исходных таблиц: колонки, типы pandas и SQL загрузки за окно."""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional

import pandas as pd

from northcart.const import DATE, DATE_KINDS, ID_TYPE, TIMESTAMP

log = logging.getLogger(__name__)


@dataclass
class Table:
    name: str
    description: str
    columns: Dict[str, str]
    sql: str  # {schema} и параметры :t_start / :t_end
    df: Optional[pd.DataFrame] = None

    @property
    def dtype(self) -> Dict[str, str]:
        return {c: t for c, t in self.columns.items() if t not in DATE_KINDS}

    @property
    def parse_dates(self) -> Dict[str, dict]:
        return {c: {"utc": True} for c, t in self.columns.items() if t in DATE_KINDS}

    @property
    def date_columns(self) -> List[str]:
        return [c for c, t in self.columns.items() if t == DATE]

    def postprocess(self) -> None:
        """DATE-столбцы → точность до дня."""
        for c in self.date_columns:
            s = self.df[c]
            not_midnight = int((s.notna() & (s != s.dt.normalize())).sum())
            if not_midnight:
                log.warning("%s.%s: %d значений не на полночь, обнуляю время", self.name, c, not_midnight)
            self.df[c] = s.dt.normalize()


@dataclass
class NorthCartTables:
    customers: Table = field(
        default_factory=lambda: Table(
            name="customers",
            description="Клиенты, зарегистрированные до T",
            columns={"customer_id": ID_TYPE, "signup_date": DATE},
            sql="""SELECT customer_id, signup_date
               FROM {schema}.customers
               WHERE signup_date < :t_end OR signup_date IS NULL""",
        )
    )
    orders: Table = field(
        default_factory=lambda: Table(
            name="orders",
            description="Заказы за окно [T-30, T)",
            columns={"order_id": ID_TYPE, "customer_id": ID_TYPE, "order_time": TIMESTAMP, "total_usd": "float64"},
            sql="""SELECT order_id, customer_id, order_time, total_usd
               FROM {schema}.orders
               WHERE order_time >= :t_start AND order_time < :t_end""",
        )
    )
    last_purchase: Table = field(
        default_factory=lambda: Table(
            name="last_purchase",
            description="Последний заказ клиента по всей истории < T",
            columns={"customer_id": ID_TYPE, "last_order_time": TIMESTAMP},
            sql="""SELECT customer_id, MAX(order_time) AS last_order_time
               FROM {schema}.orders
               WHERE order_time < :t_end AND customer_id IS NOT NULL
               GROUP BY customer_id""",
        )
    )
    sessions: Table = field(
        default_factory=lambda: Table(
            name="sessions",
            description="Сессии за окно [T-30, T)",
            columns={"session_id": ID_TYPE, "customer_id": ID_TYPE, "start_time": TIMESTAMP},
            sql="""SELECT session_id, customer_id, start_time
               FROM {schema}.sessions
               WHERE start_time >= :t_start AND start_time < :t_end""",
        )
    )
    events: Table = field(
        default_factory=lambda: Table(
            name="events",
            description="События за окно [T-30, T) с customer_id из sessions",
            columns={
                "event_id": ID_TYPE,
                "session_id": ID_TYPE,
                "timestamp": TIMESTAMP,
                "event_type": "category",
                "product_id": ID_TYPE,
                "customer_id": ID_TYPE,
            },
            sql="""SELECT e.event_id, e.session_id, e."timestamp", e.event_type,
                      e.product_id, s.customer_id
               FROM {schema}.events e
               JOIN {schema}.sessions s ON s.session_id = e.session_id
               WHERE e."timestamp" >= :t_start AND e."timestamp" < :t_end""",
        )
    )
