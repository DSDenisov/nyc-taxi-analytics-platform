-- ============================================================
-- NYC Taxi Analytics Platform — Snowflake Environment Setup
-- ============================================================
-- Provisions: warehouse, database, and schema layering
-- (raw -> staging -> intermediate -> marts) matching the dbt
-- model layers used in this project.
--
-- Run with:
--   snowsql -c <your_connection_profile> -f snowflake/01_setup.sql -o exit_on_error=true
--
-- Manual/SQL setup (not Terraform) is a deliberate scope decision
-- for this project — see docs/design_decisions.md.
-- ============================================================

CREATE WAREHOUSE IF NOT EXISTS NYC_TAXI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ;

CREATE DATABASE IF NOT EXISTS NYC_TAXI_ANALYTICS;
USE DATABASE NYC_TAXI_ANALYTICS;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS MARTS;

