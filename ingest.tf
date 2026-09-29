# Raw ingest: CSV files land in an internal stage, a daily task COPYs them into RAW.CARD_TRANSACTIONS.
# COPY INTO keeps load metadata per file, so rerunning the task never double loads a file.

resource "snowflake_file_format_csv" "card_txn" {
  database                       = snowflake_database.payments.name
  schema                         = snowflake_schema.raw.name
  name                           = "CARD_TXN_CSV"
  skip_header                    = 1
  field_optionally_enclosed_by   = "\""
  error_on_column_count_mismatch = true
  null_if                        = [""]
}

resource "snowflake_stage_internal" "card_txn" {
  database = snowflake_database.payments.name
  schema   = snowflake_schema.raw.name
  name     = "CARD_TXN_STAGE"
  comment  = "Landing zone for generated card transaction CSVs"
}

resource "snowflake_table" "card_transactions" {
  database = snowflake_database.payments.name
  schema   = snowflake_schema.raw.name
  name     = "CARD_TRANSACTIONS"
  comment  = "One row per card authorisation event, as received"

  column {
    name     = "TXN_ID"
    type     = "VARCHAR(36)"
    nullable = false
  }
  column {
    name     = "CARD_ID"
    type     = "VARCHAR(16)"
    nullable = false
  }
  column {
    name = "MERCHANT_ID"
    type = "VARCHAR(16)"
  }
  column {
    name = "MCC"
    type = "VARCHAR(4)"
  }
  column {
    name     = "AMOUNT"
    type     = "NUMBER(12,2)"
    nullable = false
  }
  column {
    name     = "CURRENCY"
    type     = "VARCHAR(3)"
    nullable = false
  }
  column {
    name = "STATUS"
    type = "VARCHAR(16)"
  }
  column {
    name     = "TXN_TS_UTC"
    type     = "TIMESTAMP_NTZ"
    nullable = false
  }
  column {
    name = "_SOURCE_FILE"
    type = "VARCHAR"
  }
  column {
    name = "_LOADED_AT"
    type = "TIMESTAMP_LTZ"
  }
}

# The table declaration is the contract. The COPY column list is derived from it, never hand written,
# and tests/test_schema_drift.py checks both the live table and every staged file against it.
locals {
  card_txn_columns        = [for c in snowflake_table.card_transactions.column : c.name]
  card_txn_source_columns = [for name in local.card_txn_columns : name if !startswith(name, "_")]
}

resource "snowflake_task" "load_card_transactions" {
  database  = snowflake_database.payments.name
  schema    = snowflake_schema.raw.name
  name      = "LOAD_CARD_TRANSACTIONS"
  warehouse = snowflake_warehouse.etl.name
  started   = true
  comment   = "Daily COPY INTO from the stage; already loaded files are skipped"

  schedule {
    using_cron = "0 6 * * * UTC"
  }

  sql_statement = <<-SQL
    COPY INTO ${snowflake_table.card_transactions.fully_qualified_name}
      (${join(", ", local.card_txn_source_columns)}, _SOURCE_FILE, _LOADED_AT)
    FROM (
      SELECT ${join(", ", [for i in range(length(local.card_txn_source_columns)) : format("$%d", i + 1)])}, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @${snowflake_stage_internal.card_txn.fully_qualified_name}
    )
    FILE_FORMAT = (FORMAT_NAME = '${snowflake_file_format_csv.card_txn.fully_qualified_name}')
    ON_ERROR = 'ABORT_STATEMENT'
  SQL
}
