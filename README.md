# neobank-analytics

Banking analytics engineering project on Snowflake, dbt Core, and Airflow.
Dimensional model for loans, deposits, and ledger reconciliation, built on
synthetic core-banking data.

## Architecture

```
raw_data/*.csv          sql/00-02 (Snowflake setup + load)
      |                         |
      v                         v
            RAW.*  (Snowflake raw tables)
                      |
                      v
         neobank_dbt: staging (views)  --  dedupe, normalize, type-cast
                      |
         +------------+------------+
         v                         v
      snapshots (SCD2)        marts (tables)
   snap_customers,             core:  dim_customers, dim_accounts, dim_date,
   snap_loans                         dim_gl_account, fct_postings
                                risk:  fct_loan_monthly, rpt_npl_by_partner
                                finance: rpt_loan_reconciliation
                      |
                      v
         neobank_airflow: neobank_dbt_nightly DAG
         (source freshness -> snapshot -> build -> docs, 03:00 daily)
```

## Repo layout

| Path | What |
|---|---|
| `sql/` | One-off Snowflake account setup: warehouse/database/role, raw table DDL, CSV load. Run manually (Snowsight), not part of dbt. |
| `raw_data/` | Synthetic source CSVs loaded by `sql/02_load_raw.sql`. |
| `neobank_dbt/` | The dbt project: staging, marts, snapshots, tests, macros. |
| `neobank_airflow/` | Astro CLI / Airflow project that orchestrates the dbt project nightly. |
| `data_profiling.md` | Raw-layer data quality findings from the day-1 load, and where each is handled downstream. |

## Prerequisites

- A Snowflake account (trial is fine)
- Python 3.10+, Docker Desktop
- [Astro CLI](https://www.astronomer.io/docs/astro/cli/install-cli) for running Airflow locally

## Setup

### 1. Snowflake account

Run these in order in a Snowsight worksheet, as `ACCOUNTADMIN` (or a role
that can create databases/warehouses/roles):

1. `sql/00_account_setup.sql` — warehouse, database, `transformer` role
2. `sql/01_create_raw.sql` — raw tables + a `landing` stage, then upload the
   6 CSVs from `raw_data/` into that stage via the Snowsight UI
3. `sql/02_load_raw.sql` — `copy into` the uploaded files, grant `transformer`
   read access on `RAW`

Each script starts with a small config block (`db_name`, `wh_name`,
`role_name`). To provision a second environment (e.g. prod), copy the
scripts, change those three literals, and run again — nothing else needs
editing. See [Environments](#environments) below.

`sql/03_day2_changes__DO_NOT_RUN_YET.sql` is a scripted "day 2" batch of
source mutations for testing incremental/SCD logic. Don't run it until
you're intentionally exercising that.

### 2. dbt (local)

```bash
cd neobank_dbt
python -m venv .venv && source .venv/bin/activate
pip install dbt-snowflake
```

dbt reads its connection from `~/.dbt/profiles.yml` locally (not from this
repo). Create a `neobank_dbt` profile there with a `dev` target pointing at
the database/role from step 1 — see `neobank_airflow/.env.example` for the
full list of fields (account, user, password, role, database, warehouse,
schema).

```bash
dbt deps      # installs dbt_utils, dbt_expectations, dbt_date
dbt build     # seeds, snapshots, models, tests, in dependency order
```

### 3. Airflow (Docker, via Astro CLI)

```bash
cd neobank_airflow
cp .env.example .env     # fill in real Snowflake values
astro dev start
```

This builds the image (installs a pinned `dbt-core`/`dbt-snowflake` into an
isolated `dbt_venv`, separate from Airflow's own dependencies) and starts 5
containers: scheduler, dag-processor, api-server (UI at
[localhost:8080](http://localhost:8080)), triggerer, postgres. `neobank_dbt/`
is bind-mounted in, so model/macro edits are picked up without a rebuild;
changes to the `Dockerfile` or `requirements.txt` need `astro dev restart`.

Two DAGs:
- `dbt_smoke_test` — single `dbt debug` task, run manually to sanity-check
  the container's dbt install and profile.
- `neobank_dbt_nightly` — the real pipeline: `dbt source freshness` ->
  `dbt snapshot` -> `dbt build` -> `dbt docs generate`, daily at 03:00.
  Starts **paused**; unpause it in the UI (or `airflow dags unpause
  neobank_dbt_nightly`) when you want it live.

## Environments

There's one Snowflake account behind `dev` and `prod`, split by database —
not two separate accounts. `dev` is the only one actually provisioned today;
`prod` is wired up end-to-end but not yet pointed at a real database.

- **dbt**: `neobank_airflow/profiles.yml` defines both targets. `prod`
  reads `SNOWFLAKE_PROD_DATABASE`/`SNOWFLAKE_PROD_SCHEMA` with **no
  fallback** to the dev values — an unset prod var fails the run loudly
  instead of silently writing into dev.
- **Airflow**: `neobank_dbt_nightly` picks its target from the `DBT_TARGET`
  env var, defaulting to `dev`. Set `DBT_TARGET=prod` in the container env
  to switch it — no code change.
- **Snowflake objects**: run `sql/00`-`02` again with `db_name`/`wh_name`/
  `role_name` changed (e.g. `neobank_prod`) to provision the prod side.

To actually promote: provision prod Snowflake objects (above), set
`SNOWFLAKE_PROD_DATABASE`/`SNOWFLAKE_PROD_SCHEMA` in `.env`, set
`DBT_TARGET=prod`.

## Data model

- **Staging** (`models/staging/core_banking/`, views): one model per raw
  table. Dedupes re-sent rows, normalizes casing/whitespace, converts
  cents to decimal EUR, casts text dates. See `data_profiling.md` for the
  specific issues each transform exists to fix.
- **Snapshots** (`snapshots/`): `snap_customers` (timestamp strategy, tracks
  `updated_at`) and `snap_loans` (check strategy, tracks `loan_status`).
  `dim_customers` does a point-in-time join against `snap_customers` so
  historical marts reflect the customer attributes *as of* each period.
- **Marts** (`models/marts/`, tables):
  - `core`: `dim_customers`, `dim_accounts`, `dim_date`, `dim_gl_account`
    (contract-enforced), `fct_postings` (incremental, merge on `posting_id`)
  - `risk`: `fct_loan_monthly` (periodic snapshot, days-past-due bucketing,
    expected loss), `rpt_npl_by_partner`
  - `finance`: `rpt_loan_reconciliation` (GL ledger vs. loan sub-ledger)
- Every mart run writes a row per model to `<schema>_audit.model_run_log`
  (`on-run-start`/`on-run-end` hooks + the `log_run_summary` macro).

## Testing & data quality

```bash
dbt build               # everything: seeds, snapshots, models, tests
dbt test --select tag:risk   # just the risk marts and their tests
dbt source freshness     # check raw tables against their freshness SLAs
```

- Schema tests (`not_null`, `unique`, `relationships`, `accepted_values`)
  plus `dbt_utils`/`dbt_expectations` tests on the marts.
- One unit test (`models/staging/core_banking/_core_banking__unit_tests.yml`)
  covers the ledger-postings dedup/normalization logic with synthetic rows.
- Two singular tests: `assert_transactions_balance` (debits = credits per
  transaction) and a custom `not_negative` generic test — both `warn`, not
  `error`, by design (finance reviews, doesn't auto-block on these).
- Named selectors in `selectors.yml` (`nightly`, `risk_month_end`) so the
  DAG doesn't need long `--select` strings.

**Note on freshness in this repo as-is**: `raw_data/*.csv` is a static,
one-time load, not a live nightly feed. `dbt source freshness` will
correctly report all 6 sources as stale until the raw tables are actually
reloaded — that's the freshness check doing its job, not a bug.
