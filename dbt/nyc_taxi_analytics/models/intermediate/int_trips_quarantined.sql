with stg as (
    select *
    from {{ ref('stg_yellow_tripdata') }}
)
select * 
from stg
where not ( {{ is_valid_trip() }} )