with stg as (
    select *
    from {{ ref('stg_yellow_tripdata') }}
)
select * 
from stg
where {{ is_valid_trip() }}
