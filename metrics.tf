locals {
  namespaces = ["argocd", "karpenter", "istio-system", "monitoring"]
  
  metric_configs = {
    "pod_status_pending" = {
      namespaces          = local.namespaces
      threshold           = 5
      comparison_operator = "GreaterThanThreshold"
      unit                = "Count"
    }
    "pod_status_failed" = {
      namespaces          = local.namespaces
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      unit                = "Count"
    }
    "pod_cpu_utilization" = {
      namespaces          = local.namespaces
      threshold           = 80
      comparison_operator = "GreaterThanThreshold"
      unit                = "Percent"
    }
    "pod_memory_utilization" = {
      namespaces          = local.namespaces
      threshold           = 85
      comparison_operator = "GreaterThanThreshold"
      unit                = "Percent"
    }
  }
  
  alarms = flatten([
    for metric_name, config in local.metric_configs : [
      for namespace in config.namespaces : {
        metric_name         = metric_name
        namespace           = namespace
        alarm_name          = "${metric_name}-${namespace}"
        threshold           = config.threshold
        comparison_operator = config.comparison_operator
        unit                = config.unit
      }
    ]
  ])
}

resource "aws_cloudwatch_metric_alarm" "insight_alarms" {
  for_each = { for alarm in local.alarms : alarm.alarm_name => alarm }
  
  alarm_name          = each.value.alarm_name
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = 1
  threshold           = each.value.threshold
  unit                = each.value.unit
  alarm_description   = "Alarm for ${each.value.metric_name} in namespace ${each.value.namespace}"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT MAX(${each.value.metric_name}) FROM SCHEMA(\"ContainerInsights\", Namespace) WHERE Namespace = '${each.value.namespace}'"
    return_data = true
    period      = 300
  }
  
  alarm_actions = [aws_sns_topic.alarm_topic.arn]
}

resource "aws_sns_topic" "alarm_topic" {
  name = "pod-metrics-alarms"
}

output "created_alarms" {
  value = {
    for k, v in aws_cloudwatch_metric_alarm.insight_alarms : k => {
      name      = v.alarm_name
      threshold = v.threshold
      operator  = v.comparison_operator
      unit      = v.unit
    }
  }
}

