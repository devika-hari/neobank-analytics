# Data profiling: NeoBank raw layer

Profiled on the day-1 load (`_loaded_at` up to 2026-11-01). Schema: `NEOBANK.RAW`.


## Summary of findings

| # | Table | Finding | Where it is handled |
|---|---|---|---|
| 1 | customers | 4 customers appear twice (old and new version) | Staging: keep latest `updated_at` |
| 2 | customers | `country` has mixed case and trailing spaces | Staging: `upper(trim())` |
| 3 | customers | 8 customers have no `risk_rating` | Keep null in staging; test with `warn`; default in mart |
| 4 | customers | Source overwrites `risk_rating`, no history | Snapshot (SCD2) |
| 5 | accounts | 1 orphan account (`A000513` → customer `C99999`) | `relationships` test; "Unknown" member in `dim_customer` |
| 6 | loans | `status` has mixed case (`ACTIVE`, `active`) | Staging: `upper(trim())` |
| 7 | loans | `interest_rate_pct` is a percentage (5.83 means 5.83%) | Staging: divide by 100, rename |
| 8 | repayments | 219 unpaid rows, but only 67 are overdue; , 2 due on the reporting date, 150 not yet due | Days-past-due logic must filter on `due_date` < reporting date |
| 9 | ledger_postings | 10 duplicate `posting_id` values, of two kinds | Staging: keep latest `_loaded_at` per `posting_id` |
| 10 | ledger_postings | `direction` has 8 spellings | Staging: normalise to `DEBIT` / `CREDIT` |
| 11 | ledger_postings | Amounts are integer cents; dates are text | Staging: convert to decimal EUR; cast to `date` |
| 12 | ledger_postings | `account_id` is null on bank-side postings (GL 1000, 3000) | Legitimate. No `not_null` test. Default dimension member |
| 13 | ledger_postings | 441 postings loaded more than 3 days after booking | Incremental model must filter on `_loaded_at`, not `booking_date` |
| 14 | ledger_postings | 3 transactions do not balance (after deduplication) | Singular test; reconciliation report |
| 15 | loans vs ledger | 2 loans: ledger balance differs from loan sub-ledger | Reconciliation model |

---

## 1. customers

**Intended grain:** one row per customer.
**Actual grain as delivered:** one row per customer version (`customer_id` + `updated_at`).

```sql
select
    count(*)                              as row_count,          -- 304
    count(distinct customer_id)           as distinct_customers, -- 300
    count(*) - count(risk_rating)         as null_risk_rating,   -- 8
    min(created_at)                       as first_created,
    max(updated_at)                       as last_updated
from neobank.raw.customers;
```

Duplicated customers, with full rows:

```sql
select *
from neobank.raw.customers
qualify count(*) over (partition by customer_id) > 1
order by customer_id, updated_at;
```

Result: `C00050`, `C00153`, `C00210`, `C00258`. Each has two rows. `created_at` is the same; `updated_at` and `risk_rating` differ. The row with the later `updated_at` is the current one.

Low-cardinality columns:

```sql
select country, count(*) from neobank.raw.customers group by 1 order by 2 desc;
-- DE, AT, NL, FR, ES plus 'de', 'DE ', 'fr', 'at', 'FR ', 'es'  -> 11 values, should be 5

select customer_type, count(*) from neobank.raw.customers group by 1;  -- RETAIL 230, SME 74
select risk_rating,   count(*) from neobank.raw.customers group by 1;  -- A-E, 8 null
select kyc_status,    count(*) from neobank.raw.customers group by 1;  -- VERIFIED 290, PENDING 14
select partner_id,    count(*) from neobank.raw.customers group by 1;  -- P01-P05
```

**Observations**

- The source sends old versions of some customers. Deduplicate in staging.
- The source normally overwrites `risk_rating`. History is lost unless we snapshot it.
- `full_name` is personal data. In a real bank it would be masked for most roles.

---

## 2. accounts

**Grain:** one row per account. Key `account_id` is unique.

```sql
select
    count(*)                        as row_count,           -- 663
    count(distinct account_id)      as distinct_accounts,   -- 663
    count(distinct customer_id)     as distinct_customers   -- 301 (customers has 300)
from neobank.raw.accounts;
```

Orphan check (account without a customer):

```sql
select a.account_id, a.customer_id, a.product_code
from neobank.raw.accounts a
left join neobank.raw.customers c
    on a.customer_id = c.customer_id
where c.customer_id is null;
-- A000513 | C99999 | CURRENT
```

Product and status:

```sql
select product_code, status, count(*) as accounts, count(credit_limit) as with_limit
from neobank.raw.accounts
group by 1, 2
order by 1, 2;
-- CURRENT 301 | SAVINGS 123 (10 CLOSED) | CREDIT_CARD 89 | PERSONAL_LOAN 119 | SME_LOAN 31
-- credit_limit is filled only for CREDIT_CARD
```

Sanity check on dates:

```sql
select count(*) from neobank.raw.accounts where closed_at < opened_at;                       -- 0
select count(*) from neobank.raw.accounts where status = 'CLOSED' and closed_at is null;     -- 0
select count(*) from neobank.raw.accounts where status = 'ACTIVE' and closed_at is not null; -- 0
```

**Observations**

- One customer can have several accounts (current, savings, card, loan).
- `credit_limit` applies to cards only. Null elsewhere means "not applicable".
- One orphan account. It has no postings, but the model must not drop it silently.

---

## 3. loans

**Grain:** one row per loan contract. Key `loan_id` is unique. Each loan has exactly one loan account.

```sql
select
    count(*)                        as row_count,          -- 150
    count(distinct loan_id)         as distinct_loans,     -- 150
    count(distinct account_id)      as distinct_accounts,  -- 150
    min(disbursement_date)          as first_disbursement, -- 2026-01-08
    max(disbursement_date)          as last_disbursement,  -- 2026-08-28
    min(interest_rate_pct)          as min_rate,           -- 3.53
    max(interest_rate_pct)          as max_rate,           -- 11.90
    sum(principal_amount)           as total_principal     -- 5,986,500.00
from neobank.raw.loans;

select status, count(*) from neobank.raw.loans group by 1;        -- ACTIVE 145, active 5
select product_code, count(*) from neobank.raw.loans group by 1;  -- PERSONAL_LOAN 119, SME_LOAN 31
select term_months, count(*) from neobank.raw.loans group by 1 order by 1;  -- 12, 24, 36, 48, 60
```

**Observations**

- `status` needs normalising.
- `interest_rate_pct` is a percentage. Store a rate (0.0583) in staging and name it clearly.
- `principal_amount` is the original amount. The outstanding balance must be derived from repayments or from the ledger.

---

## 4. repayments

**Grain:** one row per loan instalment (`loan_id` + `installment_no`). Key `repayment_id` is unique.

```sql
select
    count(*)                                   as row_count,       -- 966
    count(distinct repayment_id)               as distinct_ids,    -- 966
    count(distinct loan_id, installment_no)    as distinct_grain,  -- 966
    count(*) - count(paid_date)                as unpaid,          -- 219
    min(due_date)                              as first_due,       -- 2026-02-08
    max(due_date)                              as last_due         -- 2026-11-30
from neobank.raw.repayments;
```

Unpaid is not the same as overdue:

```sql
select
    case
        when due_date < '2026-10-31' then 'overdue'
        when due_date = '2026-10-31' then 'due today'
        else 'not yet due'
    end as bucket,
    count(*) as instalments
from neobank.raw.repayments
where paid_date is null
group by 1;
-- overdue 67 | due today 2 | not yet due 150

```

Sanity checks:

```sql
select count(*) from neobank.raw.repayments where paid_date < due_date;                       -- 0
select count(*) from neobank.raw.repayments where paid_date is not null
                                             and paid_amount <> due_amount;                   -- 0
select count(*) from neobank.raw.repayments where due_principal + due_interest <> due_amount; -- 0
```

Days past due per loan, as of 2026-10-31:

```sql
with overdue as (
    select loan_id, min(due_date) as oldest_unpaid_due_date
    from neobank.raw.repayments
    where paid_date is null
      and due_date < '2026-10-31'      -- due on the reporting date is not yet late
    group by loan_id
)

select
    case
        when o.loan_id is null then '0 current'
        when datediff('day', o.oldest_unpaid_due_date, '2026-10-31') <= 30 then '1-30'
        when datediff('day', o.oldest_unpaid_due_date, '2026-10-31') <= 60 then '31-60'
        when datediff('day', o.oldest_unpaid_due_date, '2026-10-31') <= 90 then '61-90'
        else '90+'
    end as dpd_bucket,
    count(*) as loans
from neobank.raw.loans l
left join overdue o on l.loan_id = o.loan_id
group by 1
order by 1;
-- 0 current 119 | 1-30 20 | 31-60 3 | 61-90 1 | 90+ 7
```

**Observations**

- A null `paid_date` on a future instalment is normal. Days past due must only consider instalments already due.
- No partial payments in this data. A real system has them; 
- The table holds instalments due up to 2026-11-30 only, not the full schedule to maturity.

---

## 5. ledger_postings

**Intended grain:** one row per posting. A transaction has 2 or 3 postings.
**Actual grain as delivered:** one row per posting per load (`posting_id` + `_loaded_at`), plus some exact duplicate rows.

```sql
select
    count(*)                          as row_count,             -- 31,967
    count(distinct posting_id)        as distinct_postings,     -- 31,957
    count(distinct transaction_id)    as distinct_transactions, -- 15,606
    min(booking_date)                 as first_booking,         -- 2026-01-01
    max(booking_date)                 as last_booking,          -- 2026-10-31
    max(_loaded_at)                   as last_loaded,           -- 2026-11-01 02:00:00
    min(amount_cents)                 as min_amount_cents       -- 409 (no negatives, no zeros)
from neobank.raw.ledger_postings;
```

### 5.1 Duplicates: two kinds

```sql
select
    posting_id,
    count(*)                      as copies,
    count(distinct _loaded_at)    as distinct_loads
from neobank.raw.ledger_postings
group by posting_id
having count(*) > 1
order by distinct_loads, posting_id;
-- 10 posting_ids
--   6 with distinct_loads = 1  -> exact duplicate rows (same file loaded twice)
--   4 with distinct_loads = 2  -> re-sent 2 days later with a new _loaded_at
```

Deduplication rule: keep one row per `posting_id`, the one with the latest `_loaded_at`.

```sql
select *
from neobank.raw.ledger_postings
qualify row_number() over (
    partition by posting_id
    order by _loaded_at desc
) = 1;
-- 31,957 rows
```

Why latest and not first: a re-sent posting may carry a correction. The newest version is the truth.

### 5.2 Direction values

```sql
select direction, count(*) from neobank.raw.ledger_postings group by 1 order by 2 desc;
-- 'CREDIT', 'DEBIT', 'credit', 'debit', ' CREDIT ', ' DEBIT ', 'D', 'C'
```

Normalise with `upper(left(trim(direction), 1))`, then map `D` to `DEBIT` and `C` to `CREDIT`. Anything else becomes null and a test catches it.

### 5.3 Null account_id

```sql
select
    gl_account_code,
    count(*)                         as postings,
    count(*) - count(account_id)     as without_account
from neobank.raw.ledger_postings
group by 1
order by 1;
-- 1000 and 3000: always null. All other GL codes: never null.
```

Clean pattern, so the nulls are legitimate: bank-side postings have no customer account.

### 5.4 Late-arriving postings

```sql
select
    datediff('day', to_date(booking_date), to_date(_loaded_at)) as load_lag_days,
    count(*) as postings
from neobank.raw.ledger_postings
group by 1
order by 1;
-- lag 1 day: about 31,500 postings (normal nightly load)
-- lag 4 to 20 days: 441 postings (215 transactions)
```

An incremental model that filters on `booking_date > max(booking_date)` would miss these 441 rows for ever. Filter on `_loaded_at`.

### 5.5 Booking date vs value date

```sql
select transaction_type, count(*)
from neobank.raw.ledger_postings
where booking_date <> value_date
group by 1;
-- CARD_PURCHASE only, 4,145 postings (value date 1 to 2 days later)
```

### 5.6 Balance check (debits = credits)

```sql
with deduplicated as (
    select *
    from neobank.raw.ledger_postings
    qualify row_number() over (partition by posting_id order by _loaded_at desc) = 1
),

signed as (
    select
        transaction_id,
        case upper(left(trim(direction), 1))
            when 'D' then amount_cents
            when 'C' then -amount_cents
        end as signed_cents
    from deduplicated
)

select
    transaction_id,
    sum(signed_cents) as net_cents,
    count(*)          as posting_count
from signed
group by transaction_id
having sum(signed_cents) <> 0
order by abs(net_cents) desc;
-- TXN0009623 | 1000 | 2
-- TXN0009143 |   81 | 2
-- TXN0013098 |   81 | 2
```

| How the check is run | Unbalanced transactions |
|---|---|
| No direction cleaning | about 1,373 |
| Direction cleaned, no deduplication | 13 |
| Direction cleaned and deduplicated | 3 |

Ten of the 13 are load duplicates, not accounting errors. Only 3 are real breaks, worth 11.62 EUR in total. Note the two differences of 81 cents: 490 booked as 409 is a typical digit-swap error.

### 5.7 Trial balance by GL account

```sql
with deduplicated as (
    select *
    from neobank.raw.ledger_postings
    qualify row_number() over (partition by posting_id order by _loaded_at desc) = 1
)

select
    d.gl_account_code,
    g.gl_account_name,
    g.account_class,
    sum(case upper(left(trim(d.direction), 1))
            when 'D' then d.amount_cents
            when 'C' then -d.amount_cents
        end) / 100 as net_debit_eur
from deduplicated d
join neobank.raw.gl_accounts g on d.gl_account_code = g.gl_account_code
group by 1, 2, 3
order by 1;
```

| GL | Name | Net debit (EUR) |
|---|---|---|
| 1000 | Cash and central bank balances | 53,172,454.05 |
| 1200 | Loans and advances to customers | 4,845,238.86 |
| 1300 | Credit card receivables | 27,014.60 |
| 2000 | Customer deposits | -7,888,124.81 |
| 3000 | Equity | -50,000,000.00 |
| 4000 | Interest income | -170,323.24 |
| 4100 | Fee and commission income | -7,006.19 |
| 5000 | Interest expense | 20,758.35 |
| | **Total (should be 0)** | **11.62** |

The 11.62 is exactly the three unbalanced transactions from 5.6.

---

## 6. gl_accounts

**Grain:** one row per GL account. 9 rows, key `gl_account_code` unique.

```sql
select * from neobank.raw.gl_accounts order by gl_account_code;

select distinct p.gl_account_code
from neobank.raw.ledger_postings p
left join neobank.raw.gl_accounts g on p.gl_account_code = g.gl_account_code
where g.gl_account_code is null;
-- no rows: every posting has a valid GL account
```

**Observations**

- GL 9000 (undrawn commitments, off-balance) has no postings. Undrawn exposure must be derived from `credit_limit` minus the drawn card balance.

---

## 7. Cross-table check: loan sub-ledger vs general ledger

Outstanding principal should be the same from both sides:

- Sub-ledger: `principal_amount` minus principal of paid instalments.
- Ledger: net debit balance on GL 1200 for the loan's account.

```sql
with deduplicated as (
    select *
    from neobank.raw.ledger_postings
    qualify row_number() over (partition by posting_id order by _loaded_at desc) = 1
),

ledger as (
    select
        account_id,
        sum(case upper(left(trim(direction), 1))
                when 'D' then amount_cents
                when 'C' then -amount_cents
            end) / 100 as ledger_outstanding
    from deduplicated
    where gl_account_code = '1200'
    group by account_id
),

subledger as (
    select
        l.loan_id,
        l.account_id,
        l.principal_amount
            - coalesce(sum(case when r.paid_date is not null then r.due_principal end), 0)
            as subledger_outstanding
    from neobank.raw.loans l
    left join neobank.raw.repayments r on l.loan_id = r.loan_id
    group by l.loan_id, l.account_id, l.principal_amount
)

select
    s.loan_id,
    s.subledger_outstanding,
    g.ledger_outstanding,
    g.ledger_outstanding - s.subledger_outstanding as difference
from subledger s
left join ledger g on s.account_id = g.account_id
where g.ledger_outstanding is distinct from s.subledger_outstanding
order by abs(difference) desc;
-- L00112 | 173,131.05 | 182,747.44 | 9,616.39
-- L00132 |   2,816.04 |   2,954.65 |   138.61
```

Two loans have an instalment marked as paid in `repayments` with no matching posting in the ledger. The difference equals the principal part of that instalment.

Total loan book: sub-ledger 4,835,483.86 EUR, ledger 4,845,238.86 EUR, difference 9,755.00 EUR.

---

## 8. What staging must do

| Model | Actions |
|---|---|
| `stg_core_banking__customers` | Deduplicate on `customer_id` (latest `updated_at`); `upper(trim(country))`; keep null `risk_rating` |
| `stg_core_banking__accounts` | Rename and cast only; keep the orphan |
| `stg_core_banking__loans` | `upper(trim(status))`; `interest_rate_pct / 100` as `interest_rate` |
| `stg_core_banking__repayments` | Rename and cast; add `is_paid` flag |
| `stg_core_banking__ledger_postings` | Deduplicate on `posting_id` (latest `_loaded_at`); normalise `direction`; `amount_cents / 100` as `amount`; cast `booking_date` and `value_date` to `date`; add `signed_amount` |
| `stg_core_banking__gl_accounts` | Rename and cast only |

Not for staging: fixing unbalanced transactions, inventing a customer for the orphan, filling missing risk ratings. Those are business decisions. Staging cleans format; it does not change meaning.
