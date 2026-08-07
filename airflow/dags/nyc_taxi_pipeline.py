import logging
import sys
from datetime import datetime, timedelta

import requests
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.sensors.python import PythonSensor
from airflow.sdk import DAG
from dateutil.relativedelta import relativedelta

logger = logging.getLogger(__name__)


# ingestion/ is volume-mounted into this container at /opt/airflow/project/ingestion
# (see docker-compose.yaml) — imported directly here so SOURCE_BASE_URL has exactly
# one source of truth, shared with the ingestion script itself.
sys.path.insert(0, "/opt/airflow/project/ingestion")
from config import SOURCE_BASE_URL

LAG_MONTHS = 3

def lagged_year_month(logical_date, lag_months=LAG_MONTHS):
    """Return (year, month) computed as lag_months calendar months
    before the given logical_date."""
    lagged = logical_date - relativedelta(months=lag_months)
    return lagged.year, lagged.month

def lagged_year_month_args(logical_date, lag_months=LAG_MONTHS):
    """Return '--year YYYY --month M' for the ingestion script."""
    year, month = lagged_year_month(logical_date, lag_months)
    return f"--year {year} --month {month}"

def check_source_available(logical_date, **context):
    year, month = lagged_year_month(logical_date)
    url = f"{SOURCE_BASE_URL}/yellow_tripdata_{year}-{month:02d}.parquet"

    logger.info("Checking availability for %s-%02d at %s", year, month, url)

    response = requests.head(url, timeout=30)

    if response.status_code == 200:
        logger.info("Source file for %s-%02d is available.", year, month)
        return True

    logger.info(
        "Source file for %s-%02d not yet available (HTTP %s). Will check again.",
        year, month, response.status_code,
    )
    return False


with DAG (
    dag_id="nyc_taxi_pipeline",
    description="Monthly ingestion, load, and transformation of NYC TLC Yellow Taxi trip data",
    start_date=datetime(2024, 1, 1),
    schedule="0 6 1 * *",
    catchup=False,
    tags=["nyc-taxi"],
    user_defined_macros={
        "lagged_year_month_args": lagged_year_month_args,
    }
) as dag:

    wait_for_source_file = PythonSensor(
        task_id="wait_for_source_file",
        python_callable=check_source_available,
        mode="reschedule",
        poke_interval=timedelta(days=1),
        timeout=timedelta(days=14),
    )

    ingest_month = BashOperator(
        task_id="ingest_month",
        bash_command=(
            "python /opt/airflow/project/ingestion/ingest_trip_data.py "
            "{{ lagged_year_month_args(dag_run.logical_date) }}"
        ),
        skip_on_exit_code=99,
    )

    copy_into_raw = BashOperator(
        task_id="copy_into_raw",
        bash_command=(
            "cd /opt/airflow/project/snowflake && "
            "python run_sql_script.py --file operations/load_raw.sql"
        ),
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command="cd /opt/airflow/project/dbt && dbt build"
    )

    wait_for_source_file >> ingest_month >> copy_into_raw >> dbt_build