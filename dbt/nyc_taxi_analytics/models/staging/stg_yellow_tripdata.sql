with src as (
    select * from {{ source('raw', 'yellow_tripdata') }}
),
parsed as (
    select
        *,
        REGEXP_SUBSTR(_SOURCE_FILE, 'yellow_tripdata_(\\d{4})-(\\d{2})', 1, 1, 'e', 1)::int as file_year,
        REGEXP_SUBSTR(_SOURCE_FILE, 'yellow_tripdata_(\\d{4})-(\\d{2})', 1, 1, 'e', 2)::int as file_month
    from src
)
select       VENDORID               as vendor_id
            ,TPEP_PICKUP_DATETIME   as pickup_datetime
            ,TPEP_DROPOFF_DATETIME  as dropoff_datetime
            ,PASSENGER_COUNT        as passenger_count
            ,TRIP_DISTANCE          as trip_distance
            ,RATECODEID             as rate_code_id
            ,STORE_AND_FWD_FLAG     as store_and_fwd_flag
            ,PULOCATIONID           as pu_location_id
            ,DOLOCATIONID           as do_location_id
            ,PAYMENT_TYPE           as payment_type
            ,FARE_AMOUNT            as fare_amount
            ,EXTRA                  as extra_charges
            ,MTA_TAX                as mta_tax
            ,TIP_AMOUNT             as tip_amount
            ,TOLLS_AMOUNT           as tolls_amount
            ,IMPROVEMENT_SURCHARGE  as improvement_surcharge
            ,TOTAL_AMOUNT           as total_amount
            ,CONGESTION_SURCHARGE   as congestion_surcharge
            ,AIRPORT_FEE            as airport_fee
            ,CBD_CONGESTION_FEE     as cbd_congestion_fee
            ,_INGESTED_AT           as ingested_at
            ,_SOURCE_FILE           as source_file
            ,DATE_FROM_PARTS(file_year, file_month, 1)                      as file_start_date
            ,DATEADD(month, 1, DATE_FROM_PARTS(file_year, file_month, 1))   as file_end_date

from parsed