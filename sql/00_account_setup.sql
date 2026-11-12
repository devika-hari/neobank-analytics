use role accountadmin;

-- compute: smallest size, suspends after 60s idle to protect trial credits
create warehouse if not exists neobank_wh
  warehouse_size = xsmall
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;

-- storage
create database if not exists neobank;
create schema if not exists neobank.raw;

-- role that dbt will use
create role if not exists transformer;
grant usage on warehouse neobank_wh to role transformer;
grant usage, create schema on database neobank to role transformer;

-- give the role to yourself, and keep it visible to accountadmin
set me = current_user();
grant role transformer to user identifier($me);
grant role transformer to role sysadmin;