# neobank-analytics
Banking analytics engineering project on Snowflake, dbt Core and Airflow. Dimensional model for loans, deposits and ledger reconciliation, built on synthetic data.

# dbt core setup
mkdir neobank && cd neobank
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install dbt-snowflake
dbt init neobank_dbt
dbt debug


# airflow setup
