-- ============================================================
-- NYC Taxi Analytics Platform — Snowflake Loader Role
-- ============================================================
-- Creates NYC_TAXI_LOADER_ROLE, used exclusively for COPY INTO
-- operations loading raw parquet files from the S3 external stage
-- into RAW.* tables. Deliberately separate from NYC_TAXI_DBT_ROLE:
-- dbt only ever reads from RAW, it never writes to it. The loader
-- role is the only role permitted to write to RAW, and it has no
-- access to STAGING/INTERMEDIATE/MARTS at all.
--
-- This will be the role Airflow's load step runs as, distinct from
-- the role dbt runs as for transformations.
--
-- Run with:
--   snowsql -c <your_connection_profile> -f snowflake/05_loader_role.sql -o exit_on_error=true
-- ============================================================

CREATE ROLE IF NOT EXISTS NYC_TAXI_LOADER_ROLE;

GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE NYC_TAXI_LOADER_ROLE;
GRANT USAGE ON DATABASE NYC_TAXI_ANALYTICS TO ROLE NYC_TAXI_LOADER_ROLE;
GRANT USAGE ON SCHEMA NYC_TAXI_ANALYTICS.RAW TO ROLE NYC_TAXI_LOADER_ROLE;

GRANT USAGE ON FILE FORMAT NYC_TAXI_ANALYTICS.RAW.PARQUET_FORMAT TO ROLE NYC_TAXI_LOADER_ROLE;
GRANT USAGE ON STAGE NYC_TAXI_ANALYTICS.RAW.NYC_TAXI_RAW_STAGE TO ROLE NYC_TAXI_LOADER_ROLE;

GRANT CREATE TABLE ON SCHEMA NYC_TAXI_ANALYTICS.RAW TO ROLE NYC_TAXI_LOADER_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA NYC_TAXI_ANALYTICS.RAW TO ROLE NYC_TAXI_LOADER_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA NYC_TAXI_ANALYTICS.RAW TO ROLE NYC_TAXI_LOADER_ROLE;

GRANT ROLE NYC_TAXI_LOADER_ROLE TO USER DSDENISOV;

CREATE USER IF NOT EXISTS NYC_TAXI_LOADER_SVC_USER
  RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoXeLJ1491yqkzIZ9xwYB
zmPnq8C3qo3Lc1jOcTchhndZszySRfIKvg1Qu/8rHmsuG+RIJBv9jwnAO7A0thRQ
lh03bwmZGuB8JQ2dV4BKXtoNw8HUedPODfU9T4+xOV/K34S2llVE/n6vG9lN4A+O
6qZJ02ytTsnT9XzRziuwf49THCfEloFLPdUiBQ4SeAqJWHi7MAQ2eOXkFV2Ke8nS
Si00Zbr1HKz41359UJBoLF4RM1a4kuIHYi6h3A9gLAM3GvIVci39+qeO0rdLg5qa
W/ZALc/XhLScpUvAFy5Pnk5N9GoqbE3/Vsm1RKfYrvONVKUV2Pi80c3EXoeK6Krs
QwIDAQAB'
  DEFAULT_ROLE = NYC_TAXI_LOADER_ROLE
  DEFAULT_WAREHOUSE = NYC_TAXI_WH
  DEFAULT_NAMESPACE = NYC_TAXI_ANALYTICS.RAW
  COMMENT = 'Service account for automated COPY INTO loads from S3 raw zone. Automation only, no interactive login expected.';

GRANT ROLE NYC_TAXI_LOADER_ROLE TO USER NYC_TAXI_LOADER_SVC_USER;