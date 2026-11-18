from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

DBT_PROJECT_DIR = "/usr/local/airflow/dbt/neobank_dbt"
DBT_BIN = "/usr/local/airflow/dbt_venv/bin/dbt"

with DAG(
    dag_id="dbt_smoke_test",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
) as dag:
    dbt_debug = BashOperator(
        task_id="dbt_debug",
        # --profiles-dir not needed: DBT_PROFILES_DIR is set in the Dockerfile.
        bash_command=f"{DBT_BIN} debug --project-dir {DBT_PROJECT_DIR}",
    )
