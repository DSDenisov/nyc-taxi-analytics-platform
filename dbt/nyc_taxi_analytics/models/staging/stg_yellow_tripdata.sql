with src as (
    select * from {{ source('raw', 'yellow_tripdata') }}
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
from src