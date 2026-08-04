with trips as (
    select * from {{ ref('fct_trips')}}
)
, vendors as (
    select * from {{ ref('dim_vendors')}}
)
select   vendors.vendor_id
        ,vendors.vendor_name
        ,avg(datediff(minute, pickup_datetime, dropoff_datetime)) as avg_trip_minutes
        ,avg(tip_amount / NULLIF(fare_amount,0) * 100) as avg_tip_percentage
from trips
join vendors 
    on trips.vendor_id = vendors.vendor_id
group by vendors.vendor_id, vendors.vendor_name
        