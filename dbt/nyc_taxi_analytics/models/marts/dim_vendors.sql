-- models/marts/dim_vendors.sql
with vendors as (
    select * from {{ ref('vendor_lookup') }}
)

select
    vendor_id,
    vendor_name
from vendors