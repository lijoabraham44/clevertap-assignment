###############################################################################
# VPC Flow Logs -> S3
#
# Flow logs are delivered directly to a dedicated, encrypted S3 bucket (no
# CloudWatch hop, which is cheaper at scale). Lifecycle rules tier the data
# down to colder storage and eventually expire it for cost control while
# preserving an auditable network record.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  flow_logs_bucket_name = "${var.name}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket        = local.flow_logs_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, { Name = local.flow_logs_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "tiered-retention"
    status = "Enabled"

    filter {} # apply to all objects

    transition {
      days          = var.flow_logs_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.flow_logs_transition_glacier_days
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.flow_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Allow the VPC Flow Logs service to write to the bucket.
data "aws_iam_policy_document" "flow_logs_bucket" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Enforce TLS-only access.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.flow_logs[0].arn,
      "${aws_s3_bucket.flow_logs[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_bucket[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  log_destination      = aws_s3_bucket.flow_logs[0].arn
  log_destination_type = "s3"
  traffic_type         = var.flow_logs_traffic_type
  vpc_id               = aws_vpc.this.id

  # Hive-compatible partitioning keeps Athena queries cheap at high volume.
  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-flow-logs" })

  depends_on = [aws_s3_bucket_policy.flow_logs]
}
