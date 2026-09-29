-- scratchpad.sql: ad hoc checks, run from the Snowflake VS Code extension.
-- Not part of the Terraform config. Terraform owns every object below.

-- 1. Who am I? (values for the SNOWFLAKE_* env vars)
SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE();

-- 2. After terraform apply: did the 3 objects land?
SHOW DATABASES LIKE 'PAYMENTS';
SHOW SCHEMAS IN DATABASE PAYMENTS;
SHOW WAREHOUSES LIKE 'ETL_XS';

-- 3. Ingest: files on the stage, task runs, rows loaded per file
LIST @PAYMENTS.RAW.CARD_TXN_STAGE;

SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(PAYMENTS.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'LOAD_CARD_TRANSACTIONS'))
ORDER BY scheduled_time DESC
LIMIT 10;

SELECT _source_file, COUNT(*) AS rows_loaded, MIN(_loaded_at) AS loaded_at
FROM PAYMENTS.RAW.CARD_TRANSACTIONS
GROUP BY _source_file
ORDER BY loaded_at DESC;

-- 4. Trial credit burn by warehouse, last 7 days (ACCOUNT_USAGE lags up to 3 hours)
SELECT warehouse_name, ROUND(SUM(credits_used), 2) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits DESC;
