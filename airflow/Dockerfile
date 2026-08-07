FROM apache/airflow:3.3.0

COPY ingestion/requirements.txt /tmp/ingestion-requirements.txt
COPY dbt/requirements.txt /tmp/dbt-requirements.txt

RUN pip install --no-cache-dir \
    -r /tmp/ingestion-requirements.txt \
    -r /tmp/dbt-requirements.txt