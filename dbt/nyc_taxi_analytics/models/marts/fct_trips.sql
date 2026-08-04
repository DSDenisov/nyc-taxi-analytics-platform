with trips as (
    select * from {{ ref('int_trips_valid') }}
),

pu_zones as (
    select * from {{ ref('dim_taxi_zones') }}
),

do_zones as (
    select * from {{ ref('dim_taxi_zones') }}
)
select   trips.*
        ,pu_zones.borough as pu_borough
        ,pu_zones.zone    as pu_zone
        ,do_zones.borough as do_borough
        ,do_zones.zone    as do_zone
from trips 
inner join pu_zones on trips.pu_location_id = pu_zones.location_id
inner join do_zones on trips.do_location_id = do_zones.location_id