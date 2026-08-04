with trips as (
    select * from {{ ref('fct_trips') }}
)

select
    pu_borough,
    hour(pickup_datetime) as pickup_hour,
    count(*) as trip_count,
    sum(total_amount) as total_revenue
from trips
group by pu_borough, hour(pickup_datetime)
order by pu_borough, pickup_hour