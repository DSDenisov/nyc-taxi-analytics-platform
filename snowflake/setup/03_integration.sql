-- ============================================================
-- NYC Taxi Analytics Platform — S3 Integration
-- ============================================================
-- Storage integration Snowflake uses to assume the AWS role and read
-- from the S3 raw zone. Pass 1 of 2 (see design_decisions.md 8a):
-- Snowflake generates an IAM user ARN + external ID here, which we
-- then feed back into Terraform to finish the AWS trust policy.
-- STORAGE_ALLOWED_LOCATIONS scopes this to raw/ only, matching the
-- IAM policy on the AWS side.
--
-- Run with:
--   snowsql -c <your_connection_profile> -f snowflake/03_integration.sql -o exit_on_error=true
-- ============================================================

create storage integration if not exists nyc_taxi_s3_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::246288393532:role/nyc-taxi-snowflake-storage-role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://nyc-taxi-raw-ds-dmitry-dev/raw/')
    ;
    
-- Reveals STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID, needed for Pass 2.
DESC INTEGRATION nyc_taxi_s3_integration;