output "topic_arn" { value = aws_sns_topic.product_changes.arn }
output "ops_alerts_topic_arn" { value = aws_sns_topic.ops_alerts.arn }
