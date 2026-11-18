FROM astrocrpublic.azurecr.io/runtime:3.3-12

# dbt runs in its own virtual environment, isolated from Airflow's dependencies.
# Version pinned to match the dbt-snowflake installed in the local dev venv.
RUN python -m venv /usr/local/airflow/dbt_venv && \
    /usr/local/airflow/dbt_venv/bin/pip install --no-cache-dir dbt-core==1.12.7 dbt-snowflake==1.12.5

# profiles.yml contains no secrets -- every credential is read via env_var() from
# the container's environment (populated from neobank_airflow/.env).
COPY profiles.yml /usr/local/airflow/.dbt/profiles.yml

# dbt's default lookup is ~/.dbt, which is /home/astro/.dbt for this image's user --
# not where profiles.yml above actually lives. Point it there explicitly.
ENV DBT_PROFILES_DIR=/usr/local/airflow/.dbt
