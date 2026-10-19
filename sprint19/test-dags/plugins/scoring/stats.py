import logging
from io import StringIO

import pandas as pd

from scoring.s3_utils import download_bytes_from_s3

def calculate_and_prepare_stats(
    s3_conn_id: str,
    input_task_id: str = None,
    **context,
) -> dict:
    """
    Вычисляет статистику скоринга и возвращает данные для вставки.
    
    Returns:
        dict: Статистика для вставки в таблицу через XCom
    """    
    
    logger = logging.getLogger(__name__)
    ti = context["ti"]
    execution_date = context.get("ds")
    
    # Получаем S3 key из XCom: перебираем кандидатов по приоритету,
    # fallback — любой последний XCom текущей задачи
    candidate_task_ids = [
        input_task_id,
        "score_and_filter",
        "data_processing.score_and_filter",
    ]
    s3_key = next(
        (ti.xcom_pull(task_ids=tid) for tid in candidate_task_ids if tid and ti.xcom_pull(task_ids=tid)),
        ti.xcom_pull(),
    )

    if not s3_key:
        raise ValueError("Не удалось получить S3 key из XCom")
    
    logger.info(f"Расчёт статистики из: {s3_key}")
    
    # Скачиваем scored CSV из S3
    scored_csv = download_bytes_from_s3(s3_key=s3_key, conn_id=s3_conn_id).decode("utf-8")
    df = pd.read_csv(StringIO(scored_csv))
    
    if df.empty:
        raise ValueError("Scored CSV пустой — нет данных для расчёта статистики")
    
    # Вычисляем простую статистику
    stats = {
        "scoring_date": execution_date,
        "total_clients": int(len(df)),
        "avg_churn_proba": float(df["churn_proba"].mean()),
        "min_churn_proba": float(df["churn_proba"].min()),
        "max_churn_proba": float(df["churn_proba"].max()),
    }
    
    logger.info(f"Клиентов: {stats['total_clients']}, "
                f"Avg: {stats['avg_churn_proba']:.4f}, "
                f"Min: {stats['min_churn_proba']:.4f}, "
                f"Max: {stats['max_churn_proba']:.4f}")
    
    return stats