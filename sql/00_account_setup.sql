use role accountadmin;

-- Environment config: change these three to promote this setup to another
-- environment (e.g. prod). Nothing else in this script needs to change.
set db_name   = 'neobank';       -- e.g. 'neobank_prod' for prod
set wh_name   = 'neobank_wh';    -- e.g. 'neobank_prod_wh' for prod
set role_name = 'transformer';   -- e.g. 'transformer_prod' for prod

-- compute: smallest size, suspends after 60s idle to protect trial credits
create warehouse if not exists identifier($wh_name)
  warehouse_size = xsmall
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;

-- storage
create database if not exists identifier($db_name);
create schema if not exists identifier($db_name || '.raw');

-- role that dbt will use
create role if not exists identifier($role_name);
grant usage on warehouse identifier($wh_name) to role identifier($role_name);
grant usage, create schema on database identifier($db_name) to role identifier($role_name);

-- give the role to yourself, and keep it visible to accountadmin
set me = current_user();
grant role identifier($role_name) to user identifier($me);
grant role identifier($role_name) to role sysadmin;