-- scratchpad.sql: ad hoc checks, run from the Snowflake VS Code extension.
-- Not part of the Terraform config. Terraform owns every object below.

-- 1. Who am I? (values for the SNOWFLAKE_* env vars)
SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE();

-- 2. After terraform apply: did the 3 objects land?
SHOW DATABASES LIKE 'PAYMENTS';
SHOW SCHEMAS IN DATABASE PAYMENTS;
SHOW WAREHOUSES LIKE 'ETL_XS';

-- 3. Trial credit burn by warehouse, last 7 days (ACCOUNT_USAGE lags up to 3 hours)
SELECT warehouse_name, ROUND(SUM(credits_used), 2) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits DESC;
