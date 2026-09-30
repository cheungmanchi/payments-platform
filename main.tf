terraform {
  required_version = ">= 1.6"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
  # State lives in HCP Terraform so CI can plan against it. Execution mode is Local:
  # plans run where the Snowflake credentials are (a laptop or GitHub Actions).
  cloud {
    organization = "cheungmanchi"
    workspaces {
      name = "payments-platform"
    }
  }
}

# Credentials come from env vars only. snowflake_table is still a preview resource in v2.
provider "snowflake" {
  preview_features_enabled = ["snowflake_table_resource"]
}

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
