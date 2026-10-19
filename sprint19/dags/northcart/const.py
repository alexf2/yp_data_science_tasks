"""Константы расчёта батч-признаков."""

DATA_TZ = "UTC"
TIMESTAMP = "timestamp"  # Postgres timestamp → datetime64[ns, UTC]
DATE = "date"  # Postgres date  datetime64[ns, UTC], 00:00
DATE_KINDS = (TIMESTAMP, DATE)
ID_TYPE = "Int64"  # единый тип всех идентификаторов

WINDOWS = (7, 30)
MAX_WINDOW = max(WINDOWS)

FEATURE_COLUMNS = [
    "customer_id",
    "run_date",
    "page_view_cnt_7d",
    "page_view_cnt_30d",
    "add_to_cart_cnt_7d",
    "add_to_cart_cnt_30d",
    "view_to_cart_conv_7d",
    "view_to_cart_conv_30d",
    "cart_to_purchase_conv_7d",
    "cart_to_purchase_conv_30d",
    "unique_products_7d",
    "unique_products_30d",
    "avg_session_duration_30d",
    "sessions_cnt_7d",
    "sessions_cnt_30d",
    "days_since_last_purchase",
    "orders_cnt_30d",
    "revenue_30d",
    "avg_order_value_30d",
]
