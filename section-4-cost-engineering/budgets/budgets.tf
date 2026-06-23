###############################################################################
# FinOps alerting — AWS Budgets + Cost Anomaly Detection (Terraform)
#
# Implements the "alerting thresholds" of 4b:
#   - per-team monthly budgets with 50/80/100% actual + forecast alerts,
#   - an org-level backstop budget,
#   - Savings Plan utilization budget (catch over-commitment),
#   - ML-based Cost Anomaly Detection routed to the owning teams.
#
# Alerts route by the `team` cost-allocation tag so they reach the OWNING team,
# not a generic inbox (consistent with Section 2 alerting discipline).
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

# ---- Inputs ----------------------------------------------------------------
variable "team_budgets" {
  description = "Per-team monthly budget limits in USD, keyed by the `team` tag value."
  type        = map(number)
  default = {
    ingestion = 120000
    platform  = 90000
    data      = 80000
    growth    = 60000
    shared    = 70000
  }
}

variable "org_monthly_budget_usd" {
  description = "Backstop budget for the whole account/region."
  type        = number
  default     = 420000
}

variable "alert_sns_topic_arn" {
  description = "SNS topic that fans out budget/anomaly alerts to Slack + the FinOps channel."
  type        = string
}

variable "finops_email" {
  description = "Fallback email subscriber for cost alerts."
  type        = string
  default     = "finops@clevertap.internal"
}

# ---- Per-team monthly cost budgets -----------------------------------------
resource "aws_budgets_budget" "team" {
  for_each = var.team_budgets

  name         = "team-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(each.value)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Scope the budget to this team's tagged spend. The AWS budgets tag-filter
  # format is "user:<key>$<value>"; format() avoids ${} escaping pitfalls.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:team$%s", each.key)]
  }

  # 50% / 80% / 100% of ACTUAL spend.
  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_sns_topic_arns  = [var.alert_sns_topic_arn]
      subscriber_email_addresses = [var.finops_email]
    }
  }

  # Forecast-to-exceed-100% (early warning before month-end).
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [var.alert_sns_topic_arn]
    subscriber_email_addresses = [var.finops_email]
  }
}

# ---- Org-level backstop budget ---------------------------------------------
resource "aws_budgets_budget" "org" {
  name         = "org-monthly-backstop"
  budget_type  = "COST"
  limit_amount = tostring(var.org_monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [var.alert_sns_topic_arn]
    subscriber_email_addresses = [var.finops_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [var.alert_sns_topic_arn]
    subscriber_email_addresses = [var.finops_email]
  }
}

# ---- Commitment health: Savings Plan utilization budget --------------------
# Alerts if SP utilization drops below 95% (a sign we over-committed and are
# wasting the commitment).
resource "aws_budgets_budget" "savings_plan_utilization" {
  name         = "savings-plan-utilization"
  budget_type  = "SAVINGS_PLANS_UTILIZATION"
  limit_amount = "95"
  limit_unit   = "PERCENTAGE"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "LESS_THAN"
    threshold                  = 95
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [var.alert_sns_topic_arn]
    subscriber_email_addresses = [var.finops_email]
  }
}

# ---- Cost Anomaly Detection (ML) -------------------------------------------
# Monitor spend broken down by the `team` cost-allocation tag.
resource "aws_ce_anomaly_monitor" "by_team" {
  name              = "anomaly-by-team"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "team_alerts" {
  name      = "anomaly-alerts"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.by_team.arn]

  subscriber {
    type    = "SNS"
    address = var.alert_sns_topic_arn
  }

  # Only alert on anomalies with material $ impact -> avoids noise.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["1000"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
