FROM apache/airflow:2.10.5

COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    -c "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.5/constraints-3.12.txt"
