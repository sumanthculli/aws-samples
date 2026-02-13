hcl
locals {
  tgw_attachment_metric_configs = {
    "BytesIn" = {
      threshold           = 10000000000  # 10 GB
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 2
    }
    "BytesOut" = {
      threshold           = 10000000000  # 10 GB
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 2
    }
    "PacketsIn" = {
      threshold           = 50000000
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 2
    }
    "PacketsOut" = {
      threshold           = 50000000
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 2
    }
    "PacketDropCountBlackhole" = {
      threshold           = 100
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "PacketDropCountNoRoute" = {
      threshold           = 100
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "BytesDropCountBlackhole" = {
      threshold           = 1000000  # 1 MB
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "BytesDropCountNoRoute" = {
      threshold           = 1000000  # 1 MB
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
  }
}

# Standard threshold alarms for TGW attachments with metric insights
resource "aws_cloudwatch_metric_alarm" "tgw_attachment_alarms" {
  for_each = local.tgw_attachment_metric_configs
  
  alarm_name          = "tgw-attachment-${lower(replace(each.key, "_", "-"))}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  alarm_description   = "Alarm for ${each.key} across all TGW attachments"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT ${each.value.statistic}(${each.key}) FROM SCHEMA(\"AWS/TransitGateway\", TransitGateway, TransitGatewayAttachment) GROUP BY TransitGatewayAttachment"
    return_data = true
    period      = 300
  }
  
  alarm_actions = [var.alarm_action_arn]
  ok_actions    = [var.alarm_action_arn]
  
  tags = {
    Service     = "transit-gateway"
    Resource    = "attachment"
    Severity    = contains(["PacketDropCountBlackhole", "PacketDropCountNoRoute", "BytesDropCountBlackhole", "BytesDropCountNoRoute"], each.key) ? "critical" : "warning"
    Maintenance = "false"
  }
}

# Composite alarm for critical packet drops
resource "aws_cloudwatch_composite_alarm" "tgw_attachment_packet_drops_critical" {
  alarm_name        = "tgw-attachment-packet-drops-critical"
  alarm_description = "Critical alarm when packet drops occur on any attachment"
  
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.tgw_attachment_alarms["PacketDropCountBlackhole"].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.tgw_attachment_alarms["PacketDropCountNoRoute"].alarm_name})"
  ])
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service  = "transit-gateway"
    Resource = "attachment"
    Severity = "critical"
  }
}

# Composite alarm for critical byte drops
resource "aws_cloudwatch_composite_alarm" "tgw_attachment_byte_drops_critical" {
  alarm_name        = "tgw-attachment-byte-drops-critical"
  alarm_description = "Critical alarm when byte drops occur on any attachment"
  
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.tgw_attachment_alarms["BytesDropCountBlackhole"].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.tgw_attachment_alarms["BytesDropCountNoRoute"].alarm_name})"
  ])
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service  = "transit-gateway"
    Resource = "attachment"
    Severity = "critical"
  }
}

variable "alarm_action_arn" {
  description = "ARN of Lambda function or SNS topic for alarm actions"
  type        = string
}

output "tgw_attachment_alarms" {
  value = {
    for k, v in aws_cloudwatch_metric_alarm.tgw_attachment_alarms : k => {
      name      = v.alarm_name
      threshold = v.threshold
      arn       = v.arn
    }
  }
}
