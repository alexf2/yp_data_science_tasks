"""Расчёт и проверка витрины батч-признаков."""

import logging

import pandas as pd

from northcart.const import FEATURE_COLUMNS, WINDOWS
from northcart.scheme import NorthCartTables
from northcart.utils import to_T

log = logging.getLogger(__name__)


# --- признаки ---


def safe_div(num: pd.Series, den: pd.Series) -> pd.Series:
    """num / den, при den <= 0 возвращает 0.0."""
    return num.div(den.where(den > 0)).fillna(0.0).astype("float64")


def create_features(run_date: str, data: NorthCartTables) -> pd.DataFrame:
    T = to_T(run_date)

    def win_start(w: int) -> pd.Timestamp:
        return T - pd.Timedelta(days=w)

    # данные уже отфильтрованы в SQL, здесь фильтры только для защиты
    cust = data.customers.df[~(data.customers.df.signup_date >= T)]
    ses = data.sessions.df[data.sessions.df.start_time < T]
    ordr = data.orders.df[data.orders.df.order_time < T]
    # customer_id уже из SQL JOIN
    ev = data.events.df[data.events.df.timestamp < T]
    last = data.last_purchase.df

    base = cust[["customer_id"]].drop_duplicates().set_index("customer_id")
    base["run_date"] = T.strftime("%Y-%m-%d")

    ev_feats, ses_feats = [], []
    for w in WINDOWS:
        start = win_start(w)
        e = ev[ev.timestamp >= start]

        counts = (
            e.groupby(["customer_id", "event_type"], observed=True)
            .size()
            .unstack(fill_value=0)
            .reindex(columns=["page_view", "add_to_cart", "purchase"], fill_value=0)
        )
        counts.columns = [f"{c}_cnt_{w}d" for c in counts.columns]

        products = (
            e[e.product_id.notna()].groupby("customer_id")["product_id"].nunique().rename(f"unique_products_{w}d")
        )
        ev_feats += [counts, products]

        ses_feats.append(ses[ses.start_time >= start].groupby("customer_id").size().rename(f"sessions_cnt_{w}d"))

    # средняя длина сессии за 30 дней
    s30 = ses[ses.start_time >= win_start(30)][["session_id", "customer_id"]]
    g = ev[ev.session_id.isin(s30.session_id)].groupby("session_id")["timestamp"]
    dur = (g.max() - g.min()).dt.total_seconds().rename("dur")
    s30 = s30.merge(dur, left_on="session_id", right_index=True, how="left")
    s30["dur"] = s30["dur"].fillna(0.0)
    avg_dur = s30.groupby("customer_id")["dur"].mean().rename("avg_session_duration_30d")

    # денежные признаки за 30 дней
    o30 = ordr[ordr.order_time >= win_start(30)]
    ord_feats = o30.groupby("customer_id").agg(
        orders_cnt_30d=("order_id", "nunique"),
        revenue_30d=("total_usd", "sum"),
        avg_order_value_30d=("total_usd", "mean"),
    )

    # давность покупки по всей истории (агрегат из SQL)
    days_last = (T - last.set_index("customer_id")["last_order_time"]).dt.days.rename("days_since_last_purchase")

    features = base.join(ev_feats + ses_feats + [avg_dur, ord_feats, days_last], how="left")

    cnt_cols = [c for c in features.columns if "_cnt_" in c or c.startswith("unique_products")]
    features[cnt_cols] = features[cnt_cols].fillna(0).astype("int64")
    money_cols = ["avg_session_duration_30d", "revenue_30d", "avg_order_value_30d"]
    features[money_cols] = features[money_cols].fillna(0.0).astype("float64")
    features["days_since_last_purchase"] = features["days_since_last_purchase"].fillna(-1).astype("int64")

    for w in WINDOWS:
        features[f"view_to_cart_conv_{w}d"] = safe_div(
            features[f"add_to_cart_cnt_{w}d"], features[f"page_view_cnt_{w}d"]
        )
        features[f"cart_to_purchase_conv_{w}d"] = safe_div(
            features[f"purchase_cnt_{w}d"], features[f"add_to_cart_cnt_{w}d"]
        )

    return features.reset_index()[FEATURE_COLUMNS]


def validate_features(features: pd.DataFrame) -> None:
    problems = []

    if list(features.columns) != FEATURE_COLUMNS:
        problems.append("состав колонок не совпадает с FEATURE_COLUMNS")
    if features.empty:
        problems.append("витрина пустая")
    if not features["customer_id"].is_unique:
        problems.append("customer_id не уникален")
    if features.isna().any().any():
        problems.append(f"пропуски: {features.columns[features.isna().any()].tolist()}")

    for p in ["page_view_cnt", "add_to_cart_cnt", "unique_products", "sessions_cnt"]:
        if not (features[f"{p}_7d"] <= features[f"{p}_30d"]).all():
            problems.append(f"{p}: 7d > 30d")

    if not features.filter(like="_conv_").ge(0).all().all():
        problems.append("отрицательные конверсии")
    if problems:
        raise ValueError("Витрина не прошла проверки: " + "; ".join(problems))

    log.info("✅ Витрина прошла проверки: %d строк", len(features))
