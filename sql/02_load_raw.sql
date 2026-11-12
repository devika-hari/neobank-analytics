-- STEP 2: run after the 6 CSV files are uploaded to @neobank.raw.landing
use role accountadmin;
use warehouse neobank_wh;
use schema neobank.raw;

list @landing;   -- expect 6 files

copy into customers       from @landing pattern = '.*raw_customers.*'       file_format = (format_name = csv_std);
copy into accounts        from @landing pattern = '.*raw_accounts.*'        file_format = (format_name = csv_std);
copy into loans           from @landing pattern = '.*raw_loans.*'           file_format = (format_name = csv_std);
copy into repayments      from @landing pattern = '.*raw_repayments.*'      file_format = (format_name = csv_std);
copy into ledger_postings from @landing pattern = '.*raw_ledger_postings.*' file_format = (format_name = csv_std);
copy into gl_accounts     from @landing pattern = '.*raw_gl_accounts.*'     file_format = (format_name = csv_std);

-- dbt role can read raw, now and for future tables
grant usage on schema neobank.raw to role transformer;
grant select on all tables in schema neobank.raw to role transformer;
grant select on future tables in schema neobank.raw to role transformer;

-- expected: customers 304 | accounts 663 | loans 150 | repayments 966 | ledger_postings 31967 | gl_accounts 9
select 'customers' t, count(*) n from customers union all
select 'accounts', count(*) from accounts union all
select 'loans', count(*) from loans union all
select 'repayments', count(*) from repayments union all
select 'ledger_postings', count(*) from ledger_postings union all
select 'gl_accounts', count(*) from gl_accounts;
