"""Батч-признаки NorthCart на дату run_date → S3 parquet."""

import io
import logging

import pendulum
from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException
from airflow.models import Variable
from airflow.operators.python import get_current_context
from airflow.utils.types import DagRunType

log = logging.getLogger(__name__)

# connections: задать в Admin → Connections
PG_CONN_ID = "northcart_pg"
S3_CONN_ID = "northcart_s3"

# variables: задать в Admin → Variables
# необязательная, только для ручных запусков
RUN_DATE_VAR = "batch_features_run_date"

DAG_ID = "batch_features"
DB_SCHEMA = "public"
S3_PREFIX = "batch_features"


def get_s3_bucket(conn_id: str = S3_CONN_ID) -> str:
    """Возвращает имя бакета из extra["bucket"] подключения conn_id."""
    from airflow.hooks.base import BaseHook

    bucket = BaseHook.get_connection(conn_id).extra_dejson.get("bucket", "").strip()
    if not bucket:
        raise AirflowFailException(f'В подключении {conn_id} не задан extra["bucket"]')
    return bucket


@dag(
    dag_id=DAG_ID,
    schedule="0 0 * * *",
    # tz в start_date задаёт TZ расписания: не зависит от default_timezone в airflow.cfg
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": pendulum.duration(minutes=5)},
    tags=["northcart", "features"],
)
def batch_features():

    @task
    def resolve_run_date() -> str:
        """Определяет дату среза run_date в формате YYYY-MM-DD.

        Порядок выбора:
          1. Variable `batch_features_run_date`, если она задана и не пустая.
             Разрешена только при ручном запуске (run_type = manual): из UI
             или через `airflow dags trigger`. При запуске по расписанию или
             в backfill заданная Variable — ошибка без повторов. Иначе все
             запуски писали бы в одну и ту же партицию S3.
          2. Иначе logical_date запуска, переведённая в UTC и обрезанная до
             даты. Источник для расписания, backfill, `dags trigger -e` /
             `--logical-date` и ручного запуска с датой в UI.
             В Airflow 2 при ручном запуске без даты logical_date = now(),
             и срез строится на сегодня.
          3. Если logical_date = None (Airflow 3, ручной запуск без даты и
             без Variable), задача падает с ошибкой «logical_date не задан».

        Перевод в UTC делает результат независимым от default_timezone
        в airflow.cfg и TZ сервера. Срез T = run_date 00:00 UTC, и все
        данные берутся строго до T.

        Returns:
            run_date в формате YYYY-MM-DD.

        Raises:
            AirflowFailException: Variable задана не при ручном запуске,
                logical_date не задан или дата не в формате YYYY-MM-DD.
        """
        ctx = get_current_context()
        dag_run = ctx["dag_run"]
        var_value = Variable.get(RUN_DATE_VAR, default_var=None)

        if var_value and var_value.strip():
            if dag_run.run_type != DagRunType.MANUAL:
                raise AirflowFailException(
                    f"Variable {RUN_DATE_VAR}={var_value} задана, а запуск {dag_run.run_type}. "
                    "Для расписания и backfill удалите Variable."
                )
            value, source = var_value.strip(), "Variable"
        else:
            logical_date = ctx.get("logical_date")
            if logical_date is None:  # Airflow 3, ручной запуск без даты
                raise AirflowFailException("logical_date не задан")
            value = pendulum.instance(logical_date).in_timezone("UTC").to_date_string()
            source = "logical_date"

        try:
            pendulum.from_format(value, "YYYY-MM-DD")
        except ValueError:
            raise AirflowFailException(f"run_date={value!r}: ожидается формат YYYY-MM-DD") from None

        log.info("run_date=%s (источник: %s, run_type=%s)", value, source, dag_run.run_type)
        return value

    @task
    def build_and_upload(run_date: str) -> dict:
        """Загружает данные за окно, считает витрину и пишет parquet в S3."""
        # тяжёлые импорты внутри задачи, чтобы не замедлять разбор DAG
        from airflow.providers.amazon.aws.hooks.s3 import S3Hook
        from airflow.providers.postgres.hooks.postgres import PostgresHook

        from northcart.data_operations import load_data
        from northcart.features import create_features, validate_features
        from northcart.preprocessing import prepare_data

        bucket = get_s3_bucket()

        engine = PostgresHook(postgres_conn_id=PG_CONN_ID).get_sqlalchemy_engine()
        with engine.connect() as conn:
            data = load_data(conn, DB_SCHEMA, run_date)

        prepare_data(data)
        features = create_features(run_date, data)
        validate_features(features)

        # run_date хранится в пути партиции, в файле колонка не нужна
        buf = io.BytesIO()
        features.drop(columns="run_date").to_parquet(buf, index=False, engine="pyarrow")
        size = buf.getbuffer().nbytes

        key = f"{S3_PREFIX}/run_date={run_date}/features.parquet"
        S3Hook(aws_conn_id=S3_CONN_ID).load_bytes(
            buf.getvalue(), key=key, bucket_name=bucket, replace=True  # перезапуск идемпотентен
        )

        uri = f"s3://{bucket}/{key}"
        log.info("✅ %s: %d строк, %d байт", uri, len(features), size)
        return {
            "run_date": run_date,
            "bucket": bucket,
            "key": key,
            "uri": uri,
            "rows": len(features),
            "size_bytes": size,
        }

    @task
    def verify_output(meta: dict) -> dict:
        """Проверяет, что parquet есть в S3 и совпадает с тем, что было записано."""
        import pandas as pd
        from airflow.providers.amazon.aws.hooks.s3 import S3Hook

        from northcart.const import FEATURE_COLUMNS

        hook = S3Hook(aws_conn_id=S3_CONN_ID)
        bucket, key, uri = meta["bucket"], meta["key"], meta["uri"]

        # 1. файл существует
        if not hook.check_for_key(key, bucket_name=bucket):
            raise AirflowFailException(f"Результат не найден: {uri}")

        # 2. размер совпадает и файл не пустой
        obj = hook.get_key(key, bucket_name=bucket)
        if obj.content_length == 0:
            raise AirflowFailException(f"Пустой файл: {uri}")
        if obj.content_length != meta["size_bytes"]:
            raise AirflowFailException(f"{uri}: размер {obj.content_length} байт, ожидалось {meta['size_bytes']}")

        # 3. файл читается, содержимое соответствует ожиданиям
        try:
            df = pd.read_parquet(io.BytesIO(obj.get()["Body"].read()), engine="pyarrow")
        except Exception as exc:
            raise AirflowFailException(f"{uri}: не читается как parquet: {exc}") from exc

        problems = []
        expected_cols = [c for c in FEATURE_COLUMNS if c != "run_date"]
        if list(df.columns) != expected_cols:
            problems.append(f"колонки {list(df.columns)} != {expected_cols}")
        if len(df) != meta["rows"]:
            problems.append(f"строк {len(df)}, ожидалось {meta['rows']}")
        if df.empty:
            problems.append("нет строк")
        elif not df["customer_id"].is_unique:
            problems.append("customer_id не уникален")
        if df.isna().any().any():
            problems.append(f"пропуски в {df.columns[df.isna().any()].tolist()}")

        if problems:
            raise AirflowFailException(f"{uri}: " + "; ".join(problems))

        log.info("✅ Проверен %s: %d строк x %d колонок, %d байт", uri, len(df), df.shape[1], obj.content_length)
        return {"run_date": meta["run_date"], "uri": uri, "rows": len(df)}

    verify_output(build_and_upload(resolve_run_date()))


batch_features()
