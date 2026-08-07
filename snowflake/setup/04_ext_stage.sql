-- ============================================================
-- NYC Taxi Analytics Platform — S3 External Stage
-- ============================================================
-- Creates the file format and external stage that let Snowflake
-- read parquet files from the S3 raw landing zone via the
-- nyc_taxi_s3_integration storage integration (created manually,
-- see docs/design_decisions.md for the two-pass trust policy
-- setup this depended on).
--
-- The stage is scoped to s3://<raw_bucket>/raw/ only, matching
-- both the storage integration's STORAGE_ALLOWED_LOCATIONS and
-- the ingestion script's partition root.
--
-- Run with:
--   snowsql -c <your_connection_profile> -f snowflake/04_ext_stage.sql -o exit_on_error=true
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE NYC_TAXI_ANALYTICS;
CREATE FILE FORMAT IF NOT EXISTS RAW.PARQUET_FORMAT
    TYPE = PARQUET;

CREATE STAGE IF NOT EXISTS RAW.NYC_TAXI_RAW_STAGE
    storage_integration = nyc_taxi_s3_integration
    URL = 's3://nyc-taxi-raw-ds-dmitry-dev/raw/'
    FILE_FORMAT = RAW.PARQUET_FORMAT;

LIST @RAW.NYC_TAXI_RAW_STAGE;