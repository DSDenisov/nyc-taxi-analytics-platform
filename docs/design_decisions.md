# Design Decisions — NYC Taxi Analytics Platform

This document records the architectural and engineering decisions made on this project,
including the reasoning behind them, tradeoffs considered, and known simplifications.
It exists so that a stranger cloning this repo — or an interviewer reviewing it — can
understand *why* the system looks the way it does, not just *what* it does.

---

## 1. Business Problem

A ground-transportation analytics platform for NYC taxi fleet operators and city
planners. The system ingests NYC TLC Yellow Taxi trip data on a recurring basis,
lands it reliably, transforms it into trustworthy business marts, and answers:

- Revenue and trip volume by borough and hour-of-day
- Average trip duration and tip percentage by vendor
- Anomalous/invalid trip records (negative fares, zero-distance non-zero-fare trips,
  impossible timestamps), explicitly filtered rather than silently dropped

---

## 2. Architecture Overview

```
NYC TLC public source (CloudFront)
        │  Python ingestion script (idempotent, streamed)
        ▼
S3 Raw Landing Zone (our own bucket, versioned, encrypted, private)
        │  Snowflake external stage + COPY INTO (NYC_TAXI_LOADER_ROLE)
        ▼
Snowflake RAW schema (RAW.YELLOW_TRIPDATA)
        │  dbt staging model (stg_yellow_tripdata) — NYC_TAXI_DBT_ROLE
        ▼
Snowflake STAGING schema
        │  dbt intermediate models (validity filtering / quarantine)
        ▼
Snowflake INTERMEDIATE schema (int_trips_valid, int_trips_quarantined)
        │  dbt mart models (business aggregates) — not yet built
        ▼
Snowflake MARTS schema
        │
        ▼
Analyst / BI query layer
```

Orchestration (Airflow) has not been built yet — it will trigger the ingestion
script, the `COPY INTO` load, and `dbt build` on a schedule. All of these steps are
currently run manually. See Section 9, "Current Status," for what's built.

---

## 3. Why Land Data in Our Own S3 Bucket First (Not Point Snowflake at the Public Source)

Two reasons, in order of importance:

1. **Replay without re-hitting the source.** If a Snowflake load or downstream
   transformation fails, we can rebuild from our own S3 copy — no dependency on the
   external source being available, rate-limit-safe, and immune to the source
   changing file layout or content over time. This is the general principle:
   decoupling ingestion from transformation.
2. **Auditability of a specific snapshot.** We have no control over the source. Our
   own copy, taken at ingestion time, is what we validate and reason about — not a
   moving target we don't own.

---

## 4. Cost Risk and Guardrails

Primary cost risk identified: **Snowflake warehouse compute**, not storage. Snowflake
bills compute per-second while a warehouse is in a "running" (non-suspended) state,
regardless of whether it's actively processing a query — this differs from typical
compute billing models and means an idle warehouse left un-suspended is the main way
to burn through free trial credits.

Guardrails implemented:
- `AUTO_SUSPEND = 60` (seconds) on the warehouse — aggressive by design, since this
  project prioritizes near-zero cost over avoiding cold-start latency.
- `WAREHOUSE_SIZE = 'XSMALL'` — sufficient for this data volume (tens of millions of
  rows); oversizing would be pure waste.
- S3 bucket region (`us-west-2`) chosen to match the Snowflake account's region,
  minimizing cross-region data transfer cost on `COPY INTO`, since that's the
  higher-frequency recurring cost compared to the one-time cross-region pull from
  the NYC TLC source (hosted in `us-east-1`).
- S3 lifecycle rules expire noncurrent object versions after 30 days and `_tmp/`
  scratch uploads after 1 day, preventing unbounded storage growth.

---

## 5. Terraform: Scope and State

- **Local state** is used for this project (single engineer, no concurrency risk).
  `terraform.tfstate` and `*.tfstate.backup` are git-ignored — state can contain
  sensitive resource attributes in plaintext and should never be committed.
- **Remote state (S3 + DynamoDB lock table)** is the correct production answer for
  any multi-person or CI/CD context, but is intentionally out of scope here to keep
  the project's scope realistic for a 10–20 hour build. Flagged as a known
  simplification.
- `.terraform.lock.hcl` **is** committed — it pins the exact AWS provider version so
  anyone cloning the repo gets identical provider behavior.
- **Snowflake infrastructure is provisioned manually via SQL scripts (`snowflake/`),
  not Terraform**, as a deliberate scope decision for this project. Introducing the
  Terraform Snowflake provider on top of AWS Terraform, dbt, and Airflow in the same
  project was judged to be too much simultaneous new surface area. This is planned
  for a later project once Snowflake fundamentals are solid.

---

## 6. AWS IAM Design

### Provisioning identity vs. runtime identity — two different trust tiers

- `terraform-nyc-taxi-provisioner` — the identity that runs Terraform locally.
  Scoped to S3 + IAM (currently via `AmazonS3FullAccess` + `IAMFullAccess` managed
  policies). **Known simplification:** `IAMFullAccess` is broad enough to be a real
  security review flag in a production context — a user that can create/modify IAM
  policies can technically self-escalate. The correct production fix is a
  hand-scoped policy limited to specific `iam:Create*`/`iam:Attach*` actions on
  specific resource ARN patterns. Not implemented here to avoid an hour of policy
  authoring that isn't the learning focus of this milestone.
- `nyc-taxi-ingestion-user` — dedicated, separate IAM user for the Python ingestion
  script. Least-privilege policy: `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`,
  scoped to the raw bucket's ARN only. No delete permission — see Section 7.

Root account credentials are never used for any automation in this project.

### Why a user, not a role, for the local ingestion script

A role adds indirection without removing the need for a static credential
somewhere, because a laptop (unlike Lambda/ECS) isn't AWS-managed compute that can
assume a role natively. A dedicated IAM user with its own access keys is the
pragmatic, still-least-privilege answer for local execution. When ingestion moves to
AWS-managed compute (Lambda/ECS) in a future iteration, that's the point to switch
to a role with no stored secret at all.

### Why Snowflake's S3 access uses a separate role, not this user

Two reasons:
1. **Blast radius isolation.** The ingestion user's static credentials are a
   leakable secret (local `.env`/AWS profile). Snowflake's storage integration uses
   STS-based cross-account role assumption with no static secret to leak at all. If
   one credential set leaked, the two systems' trust boundaries would remain
   separate.
2. **Distinct trust models.** An IAM role's trust policy defines *who* can assume
   it. The ingestion user authenticates via long-lived local credentials; Snowflake
   authenticates via cross-account STS assumption authorized by a trust policy
   naming Snowflake's AWS account and an external ID. Merging these into one
   role/policy would muddy the CloudTrail audit trail (two unrelated principals
   assuming the same role) and violates the "one role, one well-defined caller"
   pattern.

Snowflake's role (`nyc-taxi-snowflake-storage-role`) is scoped to `GetObject`/
`ListBucket` only — it never writes to the raw bucket, only reads via `COPY INTO`.
See Section 7b for the trust policy setup.

### Access keys not managed by Terraform

`aws_iam_access_key` was deliberately not used. Terraform-generated access keys are
written to `terraform.tfstate` in plaintext. Instead, Terraform manages the
*permission structure* (user, policy, attachment) and access keys are generated
manually via the AWS console — same tier of "acceptable for solo dev, not the
production answer" as the Snowflake password/key-pair handling below.

---

## 7. S3 Raw Zone Design

Bucket: `nyc-taxi-raw-ds-dmitry-dev`, region `us-west-2`.

- **Versioning enabled** — a bad ingestion run overwriting an object doesn't lose
  the previous good copy; supports the "replay from our own S3" principle from
  Section 3.
- **SSE-S3 (AES256) encryption** — chosen over SSE-KMS because this data is public
  taxi trip data (not sensitive) and SSE-S3 is free. SSE-KMS would be the correct
  choice for anything sensitive, given its key rotation and independent access
  revocation via CloudTrail-audited KMS policies.
- **Public access fully blocked** at the bucket level — non-negotiable baseline for
  every bucket in this project, not a case-by-case judgment call.
- **Lifecycle rules:**
  - `expire-old-version`: noncurrent object versions expire after 30 days;
    orphaned delete markers cleaned up.
  - `expire-temp-uploads`: objects under `_tmp/` prefix expire after 1 day.

### Key/partition structure

```
raw/yellow_tripdata/{year}/{month:02d}/yellow_tripdata_{year}-{month:02d}.parquet
```

Partition-style prefixes are used (rather than a flat namespace) for two reasons:
1. S3's `ListObjectsV2` can filter cheaply by prefix — this is the literal mechanism
   the idempotency check is built on (see Section 8).
2. This is the standard idiom expected by the broader AWS analytics ecosystem
   (Snowflake external stages, Athena, Glue) — a flat namespace signals a design
   that wasn't built to scale or integrate cleanly with those tools.

### Why temp objects are not deleted by the ingestion script

The ingestion IAM user deliberately has no `s3:DeleteObject` permission (see
Section 6). Rather than widening that permission — even scoped only to `_tmp/*` —
the chosen tradeoff is to let the `expire-temp-uploads` lifecycle rule clean up
scratch objects passively. This keeps the ingestion user's attack surface smaller:
even a fully leaked credential set for that user cannot delete a single object in
this bucket. The tradeoff is a maximum ~1 day of harmless leftover scratch storage,
which is judged worth it for the permission reduction.

---

## 7b. Snowflake ↔ AWS Trust: Storage Integration

Connecting Snowflake to the S3 raw zone required a two-pass process, because the AWS
IAM role's trust policy needs Snowflake's AWS IAM user ARN and a generated external
ID, but Snowflake only generates those *after* a storage integration is created
referencing the role — which must already exist.

**Pass 1:** Terraform creates the IAM role (`nyc-taxi-snowflake-storage-role`) with a
placeholder trust policy (trusting only our own AWS account). `CREATE STORAGE
INTEGRATION` in Snowflake references this role's ARN and returns
`STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`.

**Pass 2:** Those two values are fed back into Terraform (as variables, the external
ID marked `sensitive = true`) to replace the placeholder trust policy with the real
one, including an `sts:ExternalId` condition.

The external ID exists to solve the **confused deputy problem**: a trust policy that
only checks "is the caller Snowflake's AWS account" cannot distinguish Snowflake
acting on *our* behalf from Snowflake acting on another customer's behalf, since many
customers' integrations may share the same underlying Snowflake-side AWS principal.
The external ID is integration-specific; the trust policy requires both the correct
principal AND the correct external ID.

`STORAGE_ALLOWED_LOCATIONS` further scopes the integration to `s3://<bucket>/raw/`,
matching the IAM policy's own scope — defense in depth, not reliance on one layer.

Verified end-to-end with `LIST @stage` — confirmed the full cross-account trust
chain actually functions, not just that objects were created without error.

## 7c. Three Snowflake Roles, Not One Shared Role

- **`NYC_TAXI_LOADER_ROLE`** — writes to `RAW` only, via `COPY INTO` from the
  external stage. No access to `STAGING`/`INTERMEDIATE`/`MARTS`.
- **`NYC_TAXI_DBT_ROLE`** — read-only (`SELECT`) on `RAW`; full `CREATE`/`DROP`
  ownership of `STAGING`, `INTERMEDIATE`, `MARTS`. Cannot write to `RAW` under any
  circumstance — verified with a negative test (`CREATE TABLE RAW.*` fails under
  this role). Held by a dedicated service user, `NYC_TAXI_DBT_SVC_USER`
  (key-pair authenticated, no `ACCOUNTADMIN` grant, ever).
- Neither role can `CREATE WAREHOUSE`, `CREATE DATABASE`, or `CREATE ROLE` —
  verified with a negative test.

This mirrors the AWS IAM separation between the ingestion user and the Snowflake
storage role: each identity is scoped to exactly one stage of the pipeline, so a
compromise of any single credential set has a contained blast radius. Loading data
into `raw` and transforming data already in `raw` are treated as genuinely separate
concerns with separate identities — dbt is never used as a general-purpose loader.

## 7d. Loading RAW.YELLOW_TRIPDATA (COPY INTO)

Schema-on-write, not `VARIANT`: the TLC schema is documented and stable enough to
type explicitly, avoiding `VARIANT` unpacking overhead in every downstream query.
One table for all months (not one table per month) — dbt's staging layer needs a
single consistent source; per-month tables would force a `UNION ALL` that has to be
manually maintained every time a new month arrives, the same drift risk already
solved once via `_partition_prefix` in the ingestion script.

TLC's own documentation confirms the parquet schema isn't fully standardized across
years (e.g., `passenger_count`/`RatecodeID`/`payment_type` stored as `DOUBLE` in some
files, `INT64` in others; `cbd_congestion_fee` only exists from 2025 onward). Columns
with observed type drift are typed `FLOAT` rather than strict `NUMBER`, trading a
small amount of precision-purity for load robustness against a source we don't
control. `METADATA$FILENAME` is captured into `_source_file` for traceability.

**Bug found and fixed:** the first load reported `LOADED`, zero errors, on all 29
files — but `tpep_pickup_datetime`/`tpep_dropoff_datetime` were still wrong, landing
in the year 54,500,075. `COPY INTO`'s implicit `VARIANT → TIMESTAMP_NTZ` cast
assumed the underlying integer was epoch **seconds**; the source actually stores
epoch **microseconds**. Fixed with an explicit `TO_TIMESTAMP_NTZ(value::NUMBER, 6)`
(scale 6 = microseconds). Required a full `TRUNCATE` + reload, since Snowflake's
`COPY INTO` load history would otherwise skip already-"successfully" loaded files on
rerun. The S3 raw zone was unaffected, so no re-ingestion was needed — the payoff of
keeping ingestion and loading decoupled (Section 3).

This is a sharper version of the ingestion script's typo bug (Section 8): a
**successful load status does not mean correct data** — the failure here was
semantic (wrong unit interpretation), not syntactic, so nothing about the load
itself signaled a problem.

## 8. Ingestion Script Design

Location: `ingestion/` (`config.py`, `s3_client.py`, `ingest_trip_data.py`).

### Idempotency

"Rerunning ingestion for a given month must not duplicate data" is implemented as:
before any network or upload activity, `list_objects_v2` checks whether any objects
already exist under that month's partition prefix. If so, the run logs a skip and
exits 0 (success, not failure — this distinction matters for how an orchestrator
like Airflow interprets the run).

### Safe upload pattern (temp key → copy → return)

To avoid a partial/corrupted object ever existing at the real partitioned key (e.g.
if the process crashes mid-transfer), uploads go through:
1. Stream the source file directly into a `_tmp/` scratch key via `upload_fileobj`
   (no local disk write — chosen for portability toward future Lambda execution,
   where disk is ephemeral/limited, and simplicity).
2. Only after that upload completes without exception, a server-side `copy_object`
   copies the temp object to the real partitioned key.
3. The temp object is left in place for lifecycle-based expiration (see Section 7).

This guarantees the idempotency check (which looks at the *real* partitioned path)
can never see a corrupted partial object and mistakenly treat a failed run as
already-ingested.

### Streaming download, not local disk

`requests.get(..., stream=True)` piped directly into `upload_fileobj` — bounded
memory usage regardless of source file size, and no temp file cleanup logic needed
for local disk.

### A bug found and fixed during this milestone

The idempotency check originally queried a misspelled prefix
(`yellow_tripdate` vs. the correct `yellow_tripdata`, used everywhere else). This
caused **every** rerun to silently re-ingest instead of skipping — no exception, no
error, clean exit code, be cause the check simply always found zero objects under a
prefix nothing was ever written to. It was only caught by explicitly testing rerun
behavior for an already-ingested month, not by trusting a clean exit code as proof
of correctness.

**Fix:** extracted a single `_partition_prefix(year, month)` function, called by
both the idempotency check and the upload path, so the two can no longer define the
partition scheme independently and silently diverge. `DATASET_NAME` was also pulled
into a module-level constant rather than repeated as a literal string.

Design principle drawn from this: when two code paths must agree on a value or
format, that agreement should be enforced structurally (a shared function/constant),
not maintained by convention/memory. Extraction should be reserved for genuinely
shared logic — over-extracting single-use expressions into functions adds
indirection without reducing real risk.

### Credential handling

The ingestion script authenticates as `nyc-taxi-ingestion-user` via a named AWS CLI
profile (`aws configure --profile nyc-taxi-ingestion-user`), kept entirely separate
from the Terraform provisioner's `default` profile to avoid ever conflating the two
identities locally. `boto3.Session(profile_name=...)` is used explicitly rather than
relying on ambient/default credentials, so the script's identity is unambiguous.

---

## 8b. Intermediate Layer: Trip Validity Rule

Initial hypothesis: a trip is anomalous if its pickup month doesn't match its
source file's declared month (derived from `_source_file` via regex, exposed as
`file_start_date`/`file_end_date` in staging). This caught the known 58 rows with
implausible years (2001-2009), but investigation of the resulting quarantine set
showed ~180 false positives — real, valid trips filed a day or two into an
adjacent month's export, a known TLC export-batching behavior, not bad data.

Replaced with a direct plausibility rule (`macros/is_valid_trip.sql`): dropoff
must not precede pickup, and pickup must fall within a broad, dynamic date range
(2020-01-01 through one month past `CURRENT_DATE()`, avoiding hardcoded upper
bounds). The rule is defined once in a macro and referenced by both
`int_trips_valid` (`where {{ is_valid_trip() }}`) and `int_trips_quarantined`
(`where not ({{ is_valid_trip() }})`), so the split can't silently diverge.

Result: 3,870 of 108,891,604 rows quarantined (0.0036%) — 3,815 dropoff-before-
pickup (the dominant, previously-undetected category) and 55 implausibly old
pickups. Verified with a reconciliation test (`assert_trips_fully_partitioned`)
asserting `valid + quarantined == staging` row counts.

That test caught a real bug during development: the negation in
`int_trips_quarantined` was written as `where not {{ is_valid_trip() }}` without
parentheses. Since `NOT` binds tighter than `AND`, this compiled to `(NOT cond1)
AND cond2 AND cond3` instead of `NOT (cond1 AND cond2 AND cond3)` — a different,
wrong expression that silently dropped the 55 implausibly-old rows from both
models. Fixed by explicitly parenthesizing the macro call.

## 9. Current Status

Completed:
- S3 raw landing zone (Terraform), hardened per Section 7.
- Least-privilege IAM user for ingestion (Terraform).
- Idempotent Python ingestion script, backfilled 2024-01 through 2026-05
  (~108.9M rows).
- Snowflake warehouse, database, and schema layering (`raw`, `staging`,
  `intermediate`, `marts`) via manual SQL (`snowflake/`).
- Snowflake ↔ AWS storage integration and external stage, verified end-to-end
  (Section 7b).
- Three least-privilege Snowflake roles (loader, dbt, both verified with
  negative tests) — no work runs as `ACCOUNTADMIN` (Section 7c).
- `RAW.YELLOW_TRIPDATA` loaded via `COPY INTO`, all 29 files, verified correct
  after fixing the epoch-unit bug (Section 7d).
- dbt project scaffolded; `stg_yellow_tripdata` (staging) and `int_trips_valid`
  / `int_trips_quarantined` (intermediate) built and tested (Sections 8, 8b).

Not yet built:
- dbt mart models answering the three business questions from Section 1.
- Airflow DAG orchestrating ingestion → load → dbt build on a schedule.
- Data dictionary for mart tables.
- Unit tests for the ingestion script.

---

## 10. Known Simplifications (Not Production-Ready As-Is)

Recorded explicitly so they're never mistaken for oversights:

1. Terraform provisioner IAM permissions are broader (`IAMFullAccess`) than a
   production security review would accept.
2. Terraform state is local, not remote (S3 + DynamoDB lock table).
3. Snowflake infrastructure is hand-run SQL, not Terraform.
4. AWS and Snowflake credentials are static, locally-stored secrets (IAM user
   access keys; Snowflake key-pair private keys on disk — the dbt service
   user's key is unencrypted, a deliberate tradeoff for non-interactive
   automation use), not the fully production-grade answer (STS-issued
   temporary credentials, secrets manager integration, CI/CD-based OIDC
   federation).
5. No automated tests yet exist for the ingestion script (planned: unit tests
   using `moto` to mock S3 and validate idempotency/upload logic without real
   AWS calls).
6. Local dev environment briefly and accidentally used the dbt Fusion engine
   (a preview-tagged tool) instead of dbt-core, due to a `PATH` collision with
   a prior install; removed in favor of the pinned, stable dbt-core +
   dbt-snowflake combination this project is built on.
7. `dbt-core` was initially left unpinned in `requirements.txt` (only
   `dbt-snowflake` was pinned), which let pip resolve a newer `dbt-core` than
   the tested adapter version — both are now pinned to the same range.