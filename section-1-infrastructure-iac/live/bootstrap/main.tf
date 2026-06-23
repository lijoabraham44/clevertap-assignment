###############################################################################
# Backend bootstrap (run once per AWS account)
#
# Creates the S3 bucket (state) and DynamoDB table (state locking) that every
# other root module's backend points at. This config itself uses a local
# backend; after `apply`, commit the generated state or migrate it into the
# bucket it just created.
#
# Apply this in each account (dev, staging, prod) before any other stack.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "bootstrap"
      Account   = var.account_name
    }
  }
}

variable "region" {
  description = "Region to host the state bucket and lock table."
  type        = string
  default     = "us-east-1"
}

variable "account_name" {
  description = "Logical account name (dev, staging, prod) used in resource naming."
  type        = string
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "clevertap-tfstate-${var.account_name}-${data.aws_caller_identity.current.account_id}"
  lock_table_name   = "clevertap-tflock-${var.account_name}"
}

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  description = "Name of the Terraform state S3 bucket."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Name of the DynamoDB state-lock table."
  value       = aws_dynamodb_table.lock.name
}
