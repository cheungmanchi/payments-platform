# Admin stack: the identity CI uses. Applied locally by an admin, never by CI.
# Kept apart from the platform stack because CI's read-only role cannot inspect users,
# so planning these resources as CI would always report drift.

terraform {
  required_version = ">= 1.6"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
  cloud {
    organization = "cheungmanchi"
    workspaces {
      name = "payments-platform-bootstrap"
    }
  }
}

provider "snowflake" {} # admin credentials from env vars only

locals {
  # Public key body without the PEM delimiter lines, as Snowflake expects
  ci_public_key = join("", [
    for line in split("\n", replace(trimspace(file("${path.module}/ci_svc_rsa.pub")), "\r", "")) :
    line if !startswith(line, "-----")
  ])

  # Just enough for `terraform plan` on the platform stack and the drift tests
  ci_schema_object_grants = {
    table       = { type = "TABLE", name = "PAYMENTS.RAW.CARD_TRANSACTIONS", privileges = ["SELECT", "REFERENCES"] }
    stage       = { type = "STAGE", name = "PAYMENTS.RAW.CARD_TXN_STAGE", privileges = ["READ"] }
    file_format = { type = "FILE FORMAT", name = "PAYMENTS.RAW.CARD_TXN_CSV", privileges = ["USAGE"] }
    # MONITOR lets CI read task history. CI does not plan the task itself: see tests/test_schema_drift.py.
    task = { type = "TASK", name = "PAYMENTS.RAW.LOAD_CARD_TRANSACTIONS", privileges = ["MONITOR"] }
  }
}

resource "snowflake_account_role" "ci_reader" {
  name    = "CI_READER"
  comment = "Read only: CI plans the platform stack and runs the drift tests"
}

resource "snowflake_grant_privileges_to_account_role" "ci_database" {
  account_role_name = snowflake_account_role.ci_reader.name
  privileges        = ["USAGE", "MONITOR"]
  on_account_object {
    object_type = "DATABASE"
    object_name = "PAYMENTS"
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_warehouse" {
  account_role_name = snowflake_account_role.ci_reader.name
  privileges        = ["USAGE", "MONITOR"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = "ETL_XS"
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_schema" {
  account_role_name = snowflake_account_role.ci_reader.name
  # CREATE FILE FORMAT: the header test creates a TEMPORARY format, which still needs it
  privileges = ["USAGE", "MONITOR", "CREATE FILE FORMAT"]
  on_schema {
    schema_name = "PAYMENTS.RAW"
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_schema_objects" {
  for_each          = local.ci_schema_object_grants
  account_role_name = snowflake_account_role.ci_reader.name
  privileges        = each.value.privileges
  on_schema_object {
    object_type = each.value.type
    object_name = each.value.name
  }
}

resource "snowflake_service_user" "ci" {
  name              = "CI_SVC"
  comment           = "GitHub Actions. Key pair auth only; no password exists."
  default_role      = snowflake_account_role.ci_reader.name
  default_warehouse = "ETL_XS"
  rsa_public_key    = local.ci_public_key
}

resource "snowflake_grant_account_role" "ci" {
  role_name = snowflake_account_role.ci_reader.name
  user_name = snowflake_service_user.ci.name
}
