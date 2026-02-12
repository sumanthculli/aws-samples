# Get all OAM linked accounts
data "aws_oam_links" "monitoring" {}

data "aws_oam_link" "details" {
  for_each = toset(data.aws_oam_links.monitoring.arns)
  arn      = each.key
}

locals {
  # Extract account IDs from OAM link ARNs
  source_account_ids = distinct([
    for link in data.aws_oam_link.details :
    regex("arn:aws:oam:[^:]+:([0-9]+):.*", link.arn)[0]
  ])
}

# Use external data source to query NLBs with tags from each account
data "external" "nlbs_by_account" {
  for_each = toset(local.source_account_ids)
  
  program = ["bash", "${path.module}/get_nlbs.sh"]
  
  query = {
    account_id         = each.key
    role_name          = var.cross_account_role_name
    tag_key            = var.monitoring_tag_key
    tag_value          = var.monitoring_tag_value
    region             = var.region
  }
}

locals {
  # Parse NLB data from all accounts
  all_nlbs = flatten([
    for account_id, result in data.external.nlbs_by_account : [
      for nlb_arn in split(",", result.result.nlb_arns) : {
        account_id = account_id
        nlb_arn    = nlb_arn
        nlb_name   = regex("loadbalancer/(net/[^/]+/[a-z0-9]+)", nlb_arn)[0]
      } if nlb_arn != ""
    ]
  ])
  
  nlbs_map = {
    for nlb in local.all_nlbs :
    "${nlb.account_id}:${nlb.nlb_name}" => nlb
  }
}

# Create anomaly detector alarm per NLB
resource "aws_cloudwatch_metric_alarm" "nlb_tcp_reset_anomaly" {
  for_each = local.nlbs_map

  alarm_name          = "nlb-tcp-reset-anomaly-${replace(each.key, ":", "-")}"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  treat_missing_data  = "notBreaching"

  alarm_description = "Anomaly detected in TCP resets for ${each.value.nlb_name} in account ${each.value.account_id}"
  alarm_actions     = [var.sns_topic_arn]

  metric_query {
    id          = "m1"
    return_data = true
    account_id  = each.value.account_id

    metric {
      metric_name = "TCP_ELB_Reset_Count"
      namespace   = "AWS/NetworkELB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = each.value.nlb_name
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "TCP Reset Anomaly Band (2 std dev)"
    return_data = true
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN in the monitoring account"
  type        = string
}

variable "cross_account_role_name" {
  description = "IAM role name to assume in source accounts"
  type        = string
  default     = "MonitoringAccountAccessRole"
}

variable "monitoring_tag_key" {
  description = "Tag key to filter NLBs"
  type        = string
  default     = "MonitoringEnabled"
}

variable "monitoring_tag_value" {
  description = "Tag value to filter NLBs"
  type        = string
  default     = "true"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
