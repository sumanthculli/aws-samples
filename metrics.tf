locals {
  metric_namespaces = {
    "pod_status_pending" = ["argocd", "karpenter"]
  }
  
  alarms = flatten([
    for metric_name, namespaces in local.metric_namespaces : [
      for namespace in namespaces : {
        metric_name = metric_name
        namespace   = namespace
        alarm_name  = "${metric_name}-${namespace}"
      }
    ]
  ])
}

resource "aws_cloudwatch_metric_alarm" "insight_alarms" {
  for_each = { for alarm in local.alarms : alarm.alarm_name => alarm }
  
  alarm_name          = each.value.alarm_name
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
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
  name = "pod-status-alarms"
}

output "created_alarms" {
  value = {
    for k, v in aws_cloudwatch_metric_alarm.insight_alarms : k => {
      arn       = v.arn
      name      = v.alarm_name
      namespace = split("-", k)[1]
    }
  }
}


