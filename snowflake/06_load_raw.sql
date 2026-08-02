USE ROLE NYC_TAXI_LOADER_ROLE;
USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI_ANALYTICS;

CREATE TABLE IF NOT EXISTS RAW.YELLOW_TRIPDATA (
    VendorID                NUMBER,
    tpep_pickup_datetime     TIMESTAMP_NTZ,
    tpep_dropoff_datetime    TIMESTAMP_NTZ,
    passenger_count           FLOAT,
    trip_distance             FLOAT,
    RatecodeID                FLOAT,
    store_and_fwd_flag        STRING,
    PULocationID              NUMBER,
    DOLocationID              NUMBER,
    payment_type              FLOAT,
    fare_amount                FLOAT,
    extra                      FLOAT,
    mta_tax                    FLOAT,
    tip_amount                 FLOAT,
    tolls_amount                FLOAT,
    improvement_surcharge      FLOAT,
    total_amount                FLOAT,
    congestion_surcharge        FLOAT,
    Airport_fee                  FLOAT,
    cbd_congestion_fee           FLOAT,
    _ingested_at                  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file                   STRING
);

COPY INTO RAW.YELLOW_TRIPDATA (
    VendorID, tpep_pickup_datetime, tpep_dropoff_datetime, passenger_count,
    trip_distance, RatecodeID, store_and_fwd_flag, PULocationID, DOLocationID,
    payment_type, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
    improvement_surcharge, total_amount, congestion_surcharge, Airport_fee,
    cbd_congestion_fee, _source_file
)
FROM (
    SELECT
        $1:VendorID,
        $1:tpep_pickup_datetime,
        $1:tpep_dropoff_datetime,
        $1:passenger_count,
        $1:trip_distance,
        $1:RatecodeID,
        $1:store_and_fwd_flag,
        $1:PULocationID,
        $1:DOLocationID,
        $1:payment_type,
        $1:fare_amount,
        $1:extra,
        $1:mta_tax,
        $1:tip_amount,
        $1:tolls_amount,
        $1:improvement_surcharge,
        $1:total_amount,
        $1:congestion_surcharge,
        $1:Airport_fee,
        $1:cbd_congestion_fee,
        METADATA$FILENAME
    FROM @RAW.NYC_TAXI_RAW_STAGE
)
FILE_FORMAT = (FORMAT_NAME = RAW.PARQUET_FORMAT)
ON_ERROR = 'ABORT_STATEMENT';