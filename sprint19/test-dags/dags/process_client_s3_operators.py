import io
from datetime import datetime

import pandas as pd
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.amazon.aws.operators.s3 import S3CreateObjectOperator

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
S3_CONN_ID = "s3_default"
S3_BUCKET = f"{{{{ conn.{S3_CONN_ID}.extra_dejson.bucket }}}}"

RAW_KEY = "data_raw_{{ ds }}.csv"
PROCESSED_KEY = "data_processed_{{ ds }}.csv"

CHURN_THRESHOLD = 0.7

RAW_DATA_TEMPLATE = (
    "user_id,churn_proba,dt\n"
    "1987575,0.12,{{ ds }}\n"
    "19485657,0.87,{{ ds }}\n"
    "19483625,0.34,{{ ds }}"
)


# ---------------------------------------------------------------------------
# Business logic (чистая функция — легко покрыть unit-тестами)
# ---------------------------------------------------------------------------
def select_hot_users(df: pd.DataFrame, threshold: float = CHURN_THRESHOLD) -> pd.DataFrame:
    """Оставляет пользователей с вероятностью оттока >= threshold."""
    return df.loc[df["churn_proba"] >= threshold].assign(is_hot=True)


# ---------------------------------------------------------------------------
# Task callable
# ---------------------------------------------------------------------------
def process_and_upload(bucket: str, raw_key: str, processed_key: str) -> str:
    hook = S3Hook(aws_conn_id=S3_CONN_ID)

    raw_csv = hook.read_key(key=raw_key, bucket_name=bucket)
    df = pd.read_csv(io.StringIO(raw_csv))

    df_hot = select_hot_users(df)

    hook.load_string(
        string_data=df_hot.to_csv(index=False),
        key=processed_key,
        bucket_name=bucket,
        replace=True,
    )
    return processed_key


# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
with DAG(
    dag_id="S3_dag_improved_operators",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["xcom", "s3"],
) as dag:

    upload_raw_to_s3 = S3CreateObjectOperator(
        task_id="upload_raw_to_s3",
        aws_conn_id=S3_CONN_ID,
        s3_bucket=S3_BUCKET,
        s3_key=RAW_KEY,
        data=RAW_DATA_TEMPLATE,
        replace=True,
    )

    download_process_upload = PythonOperator(
        task_id="download_process_upload",
        python_callable=process_and_upload,
        op_kwargs={  # op_kwargs — templated field, Jinja отрендерится
            "bucket": S3_BUCKET,
            "raw_key": RAW_KEY,
            "processed_key": PROCESSED_KEY,
        },
    )

    upload_raw_to_s3 >> download_process_upload
    