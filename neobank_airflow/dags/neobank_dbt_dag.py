"""
Nightly dbt pipeline for NeoBank.

Order:  freshness  ->  snapshots  ->  build (models + tests)  ->  docs

Why this order
- Freshness first: if the source did not load, stop. Do not build reports on stale data.
- Snapshots before models: dimensions read from the snapshots.
- `dbt build` runs models and tests in dependency order and skips anything
  downstream of a failure.

Written for Airflow 3. On Airflow 2, use `from airflow import DAG` and
`from airflow.operators.bash import BashOperator`.
"""
import logging
import os
from datetime import datetime, timedelta

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

DBT_DIR = "/usr/local/airflow/dbt/neobank_dbt"
DBT = f"cd {DBT_DIR} && /usr/local/airflow/dbt_venv/bin/dbt"

# No real prod Snowflake database/schema is provisioned yet (see
# SNOWFLAKE_PROD_DATABASE / SNOWFLAKE_PROD_SCHEMA in .env.example), so this
# defaults to dev. Promote by setting DBT_TARGET=prod in the container env --
# no code change needed.
DBT_TARGET = os.environ.get("DBT_TARGET", "dev")

log = logging.getLogger(__name__)


def notify_failure(context):
    """Runs when a task fails after all retries.

    Logs at ERROR so it surfaces in the task log and anywhere Airflow's own
    logging is shipped (e.g. CloudWatch/Stackdriver). Swap/add a real sink --
    SlackWebhookOperator, EmailOperator -- once a Slack webhook or SMTP
    connection is configured; none exists in this project yet.
    """
    ti = context["task_instance"]
    log.error(
        "ALERT: %s.%s failed on %s. Log: %s",
        ti.dag_id, ti.task_id, context["ds"], ti.log_url,
    )


default_args = {
    "owner": "bank-analytics",
    "retries": 2,                          # retry transient errors (network, warehouse)
    "retry_delay": timedelta(minutes=5),
    "on_failure_callback": notify_failure,
}

with DAG(
    dag_id="neobank_dbt_nightly",
    description="Source freshness, snapshots, build and test",
    schedule="0 3 * * *",                  # 03:00, after the 02:00 source load
    start_date=datetime(2026, 11, 1),
    catchup=False,                         # do not run for past dates on first deploy
    max_active_runs=1,                     # never two dbt runs at the same time
    default_args=default_args,
    tags=["dbt", "neobank"],
) as dag:

    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"{DBT} source freshness --target {DBT_TARGET}",
    )

    snapshots = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"{DBT} snapshot --target {DBT_TARGET}",
    )

    build = BashOperator(
        task_id="dbt_build",
        # snapshots already ran, so exclude them here
        bash_command=f"{DBT} build --target {DBT_TARGET} --exclude resource_type:snapshot",
    )

    docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"{DBT} docs generate --target {DBT_TARGET}",
        trigger_rule="all_done",           # refresh docs even if the build failed
    )

    source_freshness >> snapshots >> build >> docs
