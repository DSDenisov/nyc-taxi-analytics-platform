USE ROLE NYC_TAXI_LOADER_ROLE;
USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI_ANALYTICS;

select current_database() as db, current_user as usr;