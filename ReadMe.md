# NYC Taxi Analytics Platform

End-to-end data pipeline for NYC TLC Yellow Taxi trip data — built as a portfolio project demonstrating production-style data engineering: idempotent ingestion, least-privilege access control across AWS and Snowflake, layered dbt transformations with automated data-quality testing, and Airflow orchestration.

## Business Problem

Answers three questions for a taxi fleet/city-planning audience:
- Revenue and trip volume by borough and hour-of-day
- Average trip duration and tip percentage by vendor
- Data quality visibility — anomalous records are quarantined and auditable, not silently dropped

## Architecture

```
NYC TLC (CloudFront) → Python ingestion (idempotent) → S3 raw zone
    → Snowflake external stage + COPY INTO → RAW
    → dbt: staging → intermediate (valid / quarantine) → marts (dim/fct + business aggregates)
    → Airflow: monthly, sensor-gated on source availability, skip-aware
```

**Stack:** AWS (S3, IAM), Snowflake, dbt, Apache Airflow (Docker/LocalExecutor), Python, Terraform, SQL.

Full architectural reasoning, tradeoffs, and known simplifications: [`docs/design_decisions.md`](docs/design_decisions.md).

## Repo Structure

```
terraform/    AWS infra (S3 raw zone, IAM users/roles, Snowflake trust policy)
snowflake/    setup/ (one-time infra) and operations/ (recurring COPY INTO)
ingestion/    Python ingestion script + unit tests (moto-mocked S3)
dbt/          staging → intermediate → marts models, tests, docs
airflow/      Dockerized orchestration (docker-compose, DAG)
docs/         design decisions, architecture rationale
```

## Setup

1. **AWS infra**: `cd terraform && terraform init && terraform apply` (requires your own `terraform.tfvars`, see `.example`)
2. **Snowflake infra**: run `snowflake/setup/*.sql` in order via SnowSQL (requires key-pair auth configured)
3. **Backfill data**: `python ingestion/ingest_trip_data.py --year YYYY --month M`
4. **dbt**: `cd dbt/nyc_taxi_analytics && dbt build` (requires `~/.dbt/profiles.yml`, see project docs)
5. **Airflow**: `cd airflow && docker compose up -d` (requires `airflow/.env`, see `.env.example`) — UI at `localhost:8080`

Each component's `requirements.txt`/`.env.example` documents its own dependencies and required environment variables.

## Data Quality

- ~108.9M rows loaded; 3,870 (0.0036%) quarantined — dominated by dropoff-before-pickup records, not the initially-suspected timestamp-year anomaly
- Idempotency enforced at both the S3 layer (partition-prefix check) and Snowflake layer (`COPY INTO` load history)
- A reconciliation test (`assert_trips_fully_partitioned`) guarantees the valid/quarantine split is a true partition of staging — no row lost, none duplicated

## Notable Engineering Decisions

- Cross-account IAM trust between AWS and Snowflake, built via the two-pass storage-integration pattern (placeholder trust policy → Snowflake-generated external ID → real trust policy)
- Three independent least-privilege identities (ingestion, loader, dbt), each verified with negative tests proving what they *can't* do, not just what they can
- Several silent, non-crashing bugs found and fixed via testing rather than assumed-correct output — documented in detail in `docs/design_decisions.md`

## Status

Core pipeline complete and functioning end-to-end. Known simplifications (local Terraform state, manual Snowflake SQL setup, local Airflow via Docker Compose) are documented explicitly in `docs/design_decisions.md`, not hidden.