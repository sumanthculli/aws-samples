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




# Anomaly detector for ProcessedBytes
resource "aws_cloudwatch_metric_alarm" "nlb_processed_bytes_anomaly" {
  alarm_name          = "nlb-processed-bytes-anomaly"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  alarm_description   = "Anomaly detection for NLB ProcessedBytes"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "m1"
    return_data = true
    
    metric {
      metric_name = "ProcessedBytes"
      namespace   = "AWS/NetworkELB"
      period      = 300
      stat        = "Sum"
    }
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "ProcessedBytes (expected)"
    return_data = true
  }
  
  alarm_actions = [aws_lambda_function.nlb_handler.arn]
}

# Anomaly detector for TCP_Target_Reset_Count
resource "aws_cloudwatch_metric_alarm" "nlb_target_reset_anomaly" {
  alarm_name          = "nlb-target-reset-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  alarm_description   = "Anomaly detection for NLB TCP Target Reset Count"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "m1"
    return_data = true
    
    metric {
      metric_name = "TCP_Target_Reset_Count"
      namespace   = "AWS/NetworkELB"
      period      = 300
      stat        = "Sum"
    }
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "TCP_Target_Reset_Count (expected)"
    return_data = true
  }
  
  alarm_actions = [aws_lambda_function.nlb_handler.arn]
}

# Using Metric Insights with Anomaly Detection
resource "aws_cloudwatch_metric_alarm" "nlb_processed_bytes_insight_anomaly" {
  alarm_name          = "nlb-processed-bytes-insight-anomaly"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  alarm_description   = "Anomaly detection for ProcessedBytes across all NLBs using metric insights"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "m1"
    expression  = "SELECT SUM(ProcessedBytes) FROM SCHEMA(\"AWS/NetworkELB\")"
    return_data = true
    period      = 300
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    return_data = true
  }
  
  alarm_actions = [aws_lambda_function.nlb_handler.arn]
}

resource "aws_cloudwatch_metric_alarm" "nlb_target_reset_insight_anomaly" {
  alarm_name          = "nlb-target-reset-insight-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  alarm_description   = "Anomaly detection for TCP_Target_Reset_Count across all NLBs"
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id          = "m1"
    expression  = "SELECT SUM(TCP_Target_Reset_Count) FROM SCHEMA(\"AWS/NetworkELB\")"
    return_data = true
    period      = 300
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    return_data = true
  }
  
  alarm_actions = [aws_lambda_function.nlb_handler.arn]
}
