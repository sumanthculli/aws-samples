locals {
  nlb_metric_configs = {
    "UnHealthyHostCount" = {
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      statistic           = "MAX"
    }
    "HealthyHostCount" = {
      threshold           = 1
      comparison_operator = "LessThanThreshold"
      statistic           = "MIN"
    }
    "TCP_Client_Reset_Count" = {
      threshold           = 50
      comparison_operator = "GreaterThanThreshold"
      statistic           = "SUM"
    }
    "TCP_Target_Reset_Count" = {
      threshold           = 50
      comparison_operator = "GreaterThanThreshold"
      statistic           = "SUM"
    }
    "ActiveFlowCount" = {
      threshold           = 10
      comparison_operator = "LessThanThreshold"
      statistic           = "SUM"
    }
    "NewFlowCount" = {
      threshold           = 5
      comparison_operator = "LessThanThreshold"
      statistic           = "SUM"
    }
    "ProcessedBytes" = {
      threshold           = 1000000
      comparison_operator = "LessThanThreshold"
      statistic           = "SUM"
    }
    "ConsumedLCUs" = {
      threshold           = 100
      comparison_operator = "GreaterThanThreshold"
      statistic           = "MAX"
    }
    "TargetTLSNegotiationErrorCount" = {
      threshold           = 10
      comparison_operator = "GreaterThanThreshold"
      statistic           = "SUM"
    }
    "ClientTLSNegotiationErrorCount" = {
      threshold           = 10
      comparison_operator = "GreaterThanThreshold"
      statistic           = "SUM"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "nlb_alarms" {
  for_each = local.nlb_metric_configs
  
  alarm_name          = "nlb-${lower(replace(each.key, "_", "-"))}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = 2
  threshold           = each.value.threshold
  alarm_description   = "Alarm for ${each.key} across all NLBs"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "q1"
    expression  = "SELECT ${each.value.statistic}(${each.key}) FROM SCHEMA(\"AWS/NetworkELB\")"
    return_data = true
    period      = 300
  }
  
  alarm_actions = [aws_lambda_function.nlb_handler.arn]
}
