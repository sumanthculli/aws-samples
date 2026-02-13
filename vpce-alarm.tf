> hcl
locals {
  vpc_endpoint_services = [
    "com.amazonaws.us-west-2.ec2",
    "com.amazonaws.us-west-2.rds",
    "com.amazonaws.us-west-2.eks",
    "com.amazonaws.us-west-2.s3",
    "com.amazonaws.us-west-2.kafka",
    "com.amazonaws.us-west-2.es",
    "com.amazonaws.us-west-2.logs",
    "com.amazonaws.us-west-2.monitoring",
    "com.amazonaws.us-west-2.dynamodb",
    "com.amazonaws.us-west-2.ecr.api",
    "com.amazonaws.us-west-2.ecr.dkr",
    "com.amazonaws.us-west-2.sts",
    "com.amazonaws.us-west-2.secretsmanager",
    "com.amazonaws.us-west-2.ssm",
    "com.amazonaws.us-west-2.kms",
    "com.amazonaws.us-west-2.lambda",
    "com.amazonaws.us-west-2.elasticloadbalancing"
  ]
  
  vpc_endpoint_metric_configs = {
    "PacketsDropped" = {
      threshold           = 100
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "RstPacketsSent" = {
      threshold           = 50
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 1
    }
    "BytesProcessed" = {
      threshold           = 1000000000  # 1 GB - for monitoring usage
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Sum"
      evaluation_periods  = 2
    }
  }
}

# VPC Endpoint alarms using metric insights
resource "aws_cloudwatch_metric_alarm" "vpc_endpoint_alarms" {
  for_each = local.vpc_endpoint_metric_configs
  
  alarm_name          = "vpc-endpoint-${lower(replace(each.key, "_", "-"))}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  alarm_description   = "Alarm for ${each.key} across all VPC Endpoints"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT ${each.value.statistic}(${each.key}) FROM SCHEMA(\"AWS/PrivateLinkEndpoints\", VPC Endpoint Id, Service Name)"
    return_data = true
    period      = 300
  }
  
  alarm_actions = [var.alarm_action_arn]
  ok_actions    = [var.alarm_action_arn]
  
  tags = {
    Service  = "vpc-endpoint"
    Severity = contains(["PacketsDropped", "RstPacketsSent"], each.key) ? "critical" : "warning"
  }
}

# Per-service VPC Endpoint packet drop alarms
resource "aws_cloudwatch_metric_alarm" "vpc_endpoint_service_packet_drops" {
  for_each = toset(local.vpc_endpoint_services)
  
  alarm_name          = "vpc-endpoint-${replace(split(".", each.value)[3], "-", "")}-packets-dropped"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 50
  alarm_description   = "Packet drops for ${each.value} VPC Endpoints"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT SUM(PacketsDropped) FROM SCHEMA(\"AWS/PrivateLinkEndpoints\", \"VPC Endpoint Id\", \"Service Name\") WHERE \"Service Name\" = '${each.value}'"
    return_data = true
    period      = 300
  }
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service     = "vpc-endpoint"
    ServiceName = each.value
    Severity    = "critical"
  }
}

# Composite alarm for critical VPC Endpoint issues
resource "aws_cloudwatch_composite_alarm" "vpc_endpoint_critical" {
  alarm_name        = "vpc-endpoint-critical"
  alarm_description = "Critical VPC Endpoint packet drops or RST packets"
  
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.vpc_endpoint_alarms["PacketsDropped"].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.vpc_endpoint_alarms["RstPacketsSent"].alarm_name})"
  ])
  
  alarm_actions = [var.alarm_action_arn]
  
  tags = {
    Service  = "vpc-endpoint"
    Severity = "critical"
  }
}

variable "alarm_action_arn" {
  description = "ARN of Lambda function or SNS topic for alarm actions"
  type        = string
}

variable "region" {
  description = "AWS region for VPC endpoints"
  type        = string
  default     = "us-west-2"
}

output "vpc_endpoint_alarms" {
  value = {
    aggregate_alarms = {
      for k, v in aws_cloudwatch_metric_alarm.vpc_endpoint_alarms : k => {
        name = v.alarm_name
        arn  = v.arn
      }
    }
    service_specific_alarms = {
      for k, v in aws_cloudwatch_metric_alarm.vpc_endpoint_service_packet_drops : k => {
        name = v.alarm_name
        arn  = v.arn
      }
    }
    composite_alarm = aws_cloudwatch_composite_alarm.vpc_endpoint_critical.arn
  }
}
