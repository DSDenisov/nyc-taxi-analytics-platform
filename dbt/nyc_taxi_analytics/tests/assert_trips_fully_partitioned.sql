-- tests/assert_trips_fully_partitioned.sql
-- Fails if any row from staging is missing from both valid/quarantined,
-- or present in both — the split must be a true partition, no overlap, no gaps.

with staging_count as (
    select count(*) as cnt from {{ ref('stg_yellow_tripdata') }}
),

valid_count as (
    select count(*) as cnt from {{ ref('int_trips_valid') }}
),

quarantined_count as (
    select count(*) as cnt from {{ ref('int_trips_quarantined') }}
)

select
    staging_count.cnt as staging_rows,
    valid_count.cnt as valid_rows,
    quarantined_count.cnt as quarantined_rows,
    valid_count.cnt + quarantined_count.cnt as combined_rows
from staging_count, valid_count, quarantined_count
where staging_count.cnt != valid_count.cnt + quarantined_count.cnt