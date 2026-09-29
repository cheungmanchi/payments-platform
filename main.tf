terraform {
  required_version = ">= 1.6"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

provider "snowflake" {} # credentials come from env vars only

resource "snowflake_database" "payments" {
  name    = "PAYMENTS"
  comment = "Portfolio: payments shaped pipeline"
}

resource "snowflake_schema" "raw" {
  database = snowflake_database.payments.name
  name     = "RAW"
}

resource "snowflake_warehouse" "etl" {
  name                = "ETL_XS"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = "true"
  initially_suspended = true
}
