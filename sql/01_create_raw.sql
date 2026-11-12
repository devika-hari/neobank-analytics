-- STEP 1: raw tables + landing stage. Run all.

use warehouse neobank_wh;

create schema if not exists neobank.raw;
use schema neobank.raw;

create or replace table customers (
  customer_id varchar, full_name varchar, customer_type varchar, country varchar, partner_id varchar,
  risk_rating varchar, kyc_status varchar, created_at timestamp_ntz, updated_at timestamp_ntz, _loaded_at timestamp_ntz);

create or replace table accounts (
  account_id varchar, customer_id varchar, product_code varchar, currency varchar, status varchar,
  credit_limit number(18,2), opened_at timestamp_ntz, closed_at timestamp_ntz, updated_at timestamp_ntz, _loaded_at timestamp_ntz);

create or replace table loans (
  loan_id varchar, account_id varchar, customer_id varchar, product_code varchar, principal_amount number(18,2),
  interest_rate_pct number(6,3), term_months number, disbursement_date date, maturity_date date,
  status varchar, updated_at timestamp_ntz, _loaded_at timestamp_ntz);

create or replace table repayments (
  repayment_id varchar, loan_id varchar, installment_no number, due_date date, due_principal number(18,2),
  due_interest number(18,2), due_amount number(18,2), paid_date date, paid_amount number(18,2), _loaded_at timestamp_ntz);

create or replace table ledger_postings (
  posting_id varchar, transaction_id varchar, account_id varchar, gl_account_code varchar, direction varchar,
  amount_cents number(38,0), currency varchar, booking_date varchar, value_date varchar,
  transaction_type varchar, description varchar, _loaded_at timestamp_ntz);

create or replace table gl_accounts (
  gl_account_code varchar, gl_account_name varchar, account_class varchar, normal_balance varchar,
  is_off_balance boolean, _loaded_at timestamp_ntz);

create or replace file format csv_std
  type = csv skip_header = 1 field_optionally_enclosed_by = '"'
  null_if = ('') empty_field_as_null = true;

create stage if not exists landing file_format = csv_std;

-- NEXT: upload the 6 files from raw_data/ into stage NEOBANK.RAW.LANDING (Snowsight UI), then run 02_load_raw.sql
