locals {
  nat_gateway_critical_metrics = {
    "PacketsDropCount" = {
      threshold           = 1000
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "ErrorPortAllocation" = {
      threshold           = 1
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "ActiveConnectionCount" = {
      threshold           = 55000  # NAT Gateway limit is 55,000
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Maximum"
      evaluation_periods  = 1
    }
  }
}

# Critical NAT Gateway alarms
resource "aws_cloudwatch_metric_alarm" "nat_gateway_critical" {
  for_each = local.nat_gateway_critical_metrics
  
  alarm_name          = "nat-gateway-${lower(replace(each.key, "_", "-"))}-critical"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  alarm_description   = "Critical: ${each.key} across all NAT Gateways"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT ${each.value.statistic}(${each.key}) FROM SCHEMA(\"AWS/NATGateway\", NatGatewayId)"
    return_data = true
    period      = 60
  }
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service  = "nat-gateway"
    Severity = "critical"
  }
}

# Composite alarm
resource "aws_cloudwatch_composite_alarm" "nat_gateway_critical_combined" {
  alarm_name        = "nat-gateway-critical-combined"
  alarm_description = "Any critical NAT Gateway issue"
  
  alarm_rule = join(" OR ", [
    for alarm in aws_cloudwatch_metric_alarm.nat_gateway_critical :
    "ALARM(${alarm.alarm_name})"
  ])
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service  = "nat-gateway"
    Severity = "critical"
  }
}

variable "alarm_action_arn" {
  type = string
}

output "nat_gateway_critical_alarms" {
  value = {
    for k, v in aws_cloudwatch_metric_alarm.nat_gateway_critical : k => v.arn
  }
}
