# NorthCart: батч-признаки клиентов (Airflow DAG)

DAG `batch_features` раз в сутки считает витрину батч-признаков клиентов на дату среза `run_date` и сохраняет её в S3:

```
s3://<bucket>/batch_features/run_date=YYYY-MM-DD/features.parquet
```

В файле одна строка на `customer_id` и 17 признаков. Колонки `run_date` в файле нет: дата хранится в пути партиции.

Граф задач:

```
resolve_run_date → build_and_upload → verify_output
```

| Задача | Что делает |
|---|---|
| `resolve_run_date` | определяет `run_date` из Variable или `logical_date` |
| `build_and_upload` | загружает из Postgres только окно `[T − 30 дней, T)` и агрегат последней покупки, выполняет предобработку, считает и проверяет витрину, пишет parquet в S3 |
| `verify_output` | проверяет, что файл есть в S3, читается, а число строк, размер и колонки совпадают с записанными |

---

## 1. Версии

| Компонент | Версия |
|---|---|
| Docker-образ | `apache/airflow:2.10.5` |
| Python | 3.12 (стоит в образе по умолчанию) |
| Зависимости | `requirements.txt`, версии фиксирует constraints-файл Airflow 2.10.5 |

Все нужные пакеты (providers postgres и amazon, pandas, SQLAlchemy 1.4, pyarrow) уже есть в официальном образе. Дополнительно устанавливать ничего не нужно. `requirements.txt` нужен для установки на чистом окружении и как перечень зависимостей.

---

## 2. Куда положить код

Файлы кладутся в каталог `dags/` стандартной установки Airflow через docker-compose (в контейнере это `/opt/airflow/dags`):

```
<airflow-project>/
├── docker-compose.yaml
├── requirements.txt
├── dags/
│   ├── calculate_batch_features.py   # DAG batch_features
│   └── northcart/
│       ├── __init__.py
│       ├── const.py                  # константы: TZ, окна, список признаков
│       ├── utils.py                  # to_T, to_db: граница среза и перевод в naive UTC
│       ├── scheme.py                 # Table, NorthCartTables: колонки, типы, SQL по окну
│       ├── data_operations.py        # load_data: загрузка из Postgres
│       ├── preprocessing.py          # drop_null_keys, dedup_events, prepare_data
│       └── features.py               # safe_div, create_features, validate_features
├── logs/
├── plugins/
└── config/
```

Airflow сам добавляет `dags/` в `sys.path`, поэтому импорты `from northcart.… import …` работают без дополнительной настройки.

---

## 3. Запуск окружения

Возьмите стандартный `docker-compose.yaml` для Airflow 2.10.5:

```bash
curl -LfO 'https://airflow.apache.org/docs/apache-airflow/2.10.5/docker-compose.yaml'
mkdir -p ./dags ./logs ./plugins ./config
echo -e "AIRFLOW_UID=$(id -u)" > .env
```

Добавьте в раздел `x-airflow-common.environment`:

```yaml
# форма с полем Logical date при ручном запуске из UI
AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS: 'true'
```

Запустите:

```bash
docker compose up airflow-init
docker compose up -d
```

UI: http://localhost:8080, логин и пароль по умолчанию `airflow` / `airflow`.

### Если нужно доустановить зависимости

Если `requirements.txt` расширится или используется не официальный образ, соберите свой образ. Положите рядом с `docker-compose.yaml` такой `Dockerfile`:

```dockerfile
FROM apache/airflow:2.10.5
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir "apache-airflow==2.10.5" -r /requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.5/constraints-3.12.txt"
```

В `docker-compose.yaml` закомментируйте `image:` и раскомментируйте `build: .`, затем выполните `docker compose build && docker compose up -d`.

### Проверка окружения

```bash
docker compose exec airflow-scheduler python -c \
  "import pandas, sqlalchemy, pyarrow; print(pandas.__version__, sqlalchemy.__version__, pyarrow.__version__)"
docker compose exec airflow-scheduler airflow dags list-import-errors
```

---

## 4. Connections

Задаются в **Admin → Connections** или через переменные окружения `AIRFLOW_CONN_*` в `docker-compose.yaml`.

### 4.1. `northcart_pg`: исходные данные в PostgreSQL

| Поле | Значение |
|---|---|
| Connection Id | `northcart_pg` |
| Connection Type | `Postgres` |
| Host | `<host>.mdb.yandexcloud.net` |
| Port | `6432` |
| Database (Schema) | `<имя базы>` |
| Login | `<пользователь>` |
| Password | `<пароль>` |


Таблицы берутся из схемы `public` (константа `DB_SCHEMA` в DAG). Нужны права на `SELECT` из таблиц `customers`, `sessions`, `events` и `orders`.

Тот же connection через env:

```yaml
AIRFLOW_CONN_NORTHCART_PG: 'postgresql://<user>:<password>@<host>:6432/<database>?sslmode=require'
```

### 4.2. `northcart_s3`: хранилище результата (Yandex Object Storage / S3)

| Поле | Значение |
|---|---|
| Connection Id | `northcart_s3` |
| Connection Type | `Amazon Web Services` |
| AWS Access Key ID (Login) | `<access key>` |
| AWS Secret Access Key (Password) | `<secret key>` |
| Extra | см. ниже |

```json
{
  "endpoint_url": "https://storage.yandexcloud.net",
  "region_name": "ru-central1",
  "bucket": "<имя бакета>"
}
```

`bucket` — нестандартный ключ, его читает DAG (`get_s3_bucket`). S3Hook этот ключ игнорирует. Если `bucket` не задан, задача `build_and_upload` падает ещё до загрузки данных. Нужны права на запись и чтение объектов по префиксу `batch_features/`.

Тот же connection через env:

```yaml
AIRFLOW_CONN_NORTHCART_S3: >-
  {"conn_type": "aws", "login": "<access key>", "password": "<secret key>",
   "extra": {"endpoint_url": "https://storage.yandexcloud.net",
             "region_name": "ru-central1", "bucket": "<имя бакета>"}}
```


---

## 5. Variables

| Key | Обязательная | Значение | Назначение |
|---|---|---|---|
| `batch_features_run_date` | нет | `YYYY-MM-DD` | дата среза для **ручного** запуска |

Задаётся в **Admin → Variables** или из CLI. Через env её задавать **не нужно**: такую переменную нельзя удалить из UI.

Если Variable задана, а запуск не ручной (по расписанию или backfill), задача `resolve_run_date` намеренно падает с ошибкой. Иначе все запуски писали бы в одну и ту же партицию. После ручного запуска Variable нужно удалить.

---

## 6. Как определяется `run_date`

1. Variable `batch_features_run_date`, если она задана и не пустая. Разрешена только при ручном запуске.
2. Иначе `logical_date` запуска, переведённая в UTC и обрезанная до даты.
3. Если `logical_date = None` (Airflow 3, ручной запуск без даты и без Variable), запуск падает с ошибкой «logical_date не задан».

Срез `T = run_date 00:00 UTC`. Все данные берутся строго до `T`, окна признаков равны `[T − 7 дней, T)` и `[T − 30 дней, T)`. Временные метки в БД хранятся без часового пояса и считаются UTC. Расписание задано в UTC через `start_date`, поэтому результат не зависит от `default_timezone` в `airflow.cfg` и от TZ сервера.

При запуске по расписанию запуск с `logical_date = D` стартует в `D + 1` 00:00 UTC и строит срез на `D`.

---

## 7. Режимы запуска

| № | Режим | Как запустить | Откуда `run_date` |
|---|---|---|---|
| 1 | UI, через Variable | Admin → Variables: `batch_features_run_date = 2025-09-01`, затем ▶ Trigger DAG | Variable |
| 2 | UI, с датой | ▶ Trigger DAG, поле Logical date `2025-10-09 00:00:00` (UI в UTC) | logical_date |
| 3 | UI, Airflow 3, без даты и Variable | ▶ Trigger DAG | ошибка «logical_date не задан» |
| 4 | UI, Airflow 2, без даты и Variable | ▶ Trigger DAG | logical_date = now(), срез на сегодня |
| 5 | CLI, через Variable | `airflow variables set batch_features_run_date 2025-09-01`<br>`airflow dags trigger batch_features` | Variable |
| 6 | CLI, с датой | Airflow 2: `airflow dags trigger batch_features -e 2025-10-09` | logical_date |
| 7 | Backfill | `airflow dags backfill batch_features -s 2025-10-01 -e 2025-10-03` (Variable удалена) | logical_date каждого запуска |
| 8 | По расписанию | `0 0 * * *`, DAG снят с паузы (Variable удалена) | logical_date интервала |
| — | Тест без планировщика | `airflow dags test batch_features 2025-10-09` | logical_date |

Перед ручным запуском DAG нужно снять с паузы. При `catchup=False` после снятия паузы планировщик сразу создаст один запуск за последний завершённый интервал. Данные заканчиваются 2025-11-01, поэтому у такого среза почти все признаки будут нулевыми. Это корректный результат.

---

## 8. Проверка результата

Быстрая проверка:

```bash
docker compose exec airflow-scheduler airflow dags test batch_features 2025-10-09
```

Ожидаемый результат для среза `2025-10-09`:

| Что | Значение |
|---|---|
| customers | 17 641 строк |
| orders в окне | 528 |
| sessions в окне | 1 754 |
| events в окне | 11 487 |
| Строк в витрине | 17 641 |
| Колонок в parquet | 18 (`customer_id` + 17 признаков) |

В логе `verify_output` должна быть строка:

```
✅ Проверен s3://<bucket>/batch_features/run_date=2025-10-09/features.parquet: 17641 строк x 18 колонок, ... байт
```

Повторный запуск за ту же дату перезаписывает тот же объект в S3.

---

## 9. Признаки

| Признак | Формула | Если данных нет |
|---|---|---|
| `page_view_cnt_7d`, `_30d` | число событий `page_view` в окне | 0 |
| `add_to_cart_cnt_7d`, `_30d` | число событий `add_to_cart` в окне | 0 |
| `view_to_cart_conv_7d`, `_30d` | add_to_cart / page_view | 0 |
| `cart_to_purchase_conv_7d`, `_30d` | purchase / add_to_cart | 0 |
| `unique_products_7d`, `_30d` | nunique(product_id), только события с заданным product_id | 0 |
| `avg_session_duration_30d` | среднее (max − min timestamp событий) по сессиям из окна, в секундах | 0 |
| `sessions_cnt_7d`, `_30d` | число сессий с `start_time` в окне | 0 |
| `days_since_last_purchase` | floor((T − последний заказ) / 1 день) по всей истории до T | −1 |
| `orders_cnt_30d` | число заказов за 30 дней | 0 |
| `revenue_30d` | сумма `total_usd` за 30 дней | 0.0 |
| `avg_order_value_30d` | средний `total_usd` за 30 дней | 0.0 |

Каркас витрины составляют клиенты с `signup_date < T` (или с пустым `signup_date`). Клиенты, зарегистрированные после среза, в витрину не попадают.

---

