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
        │  Snowflake external stage + COPY INTO (not yet built)
        ▼
Snowflake RAW schema
        │  dbt staging models
        ▼
Snowflake STAGING schema
        │  dbt intermediate models (dedupe, anomaly filtering)
        ▼
Snowflake INTERMEDIATE schema
        │  dbt mart models (business aggregates)
        ▼
Snowflake MARTS schema
        │
        ▼
Analyst / BI query layer
```

Orchestration (Airflow) and the dbt project itself have not been built yet as of this
document's current state — see Section 9, "Current Status."

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
  higher-frequency recurring cost.
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

### Why Snowflake's future S3 access will use a separate role, not this user

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

Snowflake's eventual role will be scoped to `GetObject`/`ListBucket` only — it never
writes to the raw bucket, only reads via `COPY INTO`.

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

## Current Status

Completed:
- S3 raw landing zone (Terraform), hardened per Section 7.
- Least-privilege IAM user for ingestion (Terraform).
- Idempotent Python ingestion script, backfilled 2024-01 through 2026-05.
- Snowflake warehouse, database, and schema layering (`raw`, `staging`,
  `intermediate`, `marts`) via manual SQL (`snowflake/setup.sql`).
- Dedicated Snowflake role.

Not yet built:

- Snowflake storage integration / external stage / `COPY INTO` from S3 into the
  `raw` schema.
- dbt project (staging, intermediate, mart models; tests; docs).
- Airflow DAG orchestrating the end-to-end pipeline.
- Data dictionary for mart tables.

---

## Known Simplifications (Not Production-Ready As-Is)

Recorded explicitly so they're never mistaken for oversights:

1. Terraform provisioner IAM permissions are broader (`IAMFullAccess`) than a
   production security review would accept.
2. Terraform state is local, not remote (S3 + DynamoDB lock table).
3. Snowflake infrastructure is hand-run SQL, not Terraform.
4. AWS and Snowflake credentials are static, locally-stored secrets (IAM user
   access keys; Snowflake key-pair private key on disk), not the fully
   production-grade answer (STS-issued temporary credentials, secrets manager
   integration, CI/CD-based OIDC federation).
5. No automated tests yet exist for the ingestion script (planned: unit tests using
   `moto` to mock S3 and validate idempotency/upload logic without real AWS calls).