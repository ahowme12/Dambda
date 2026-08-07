output "queue_url" { value = aws_sqs_queue.review_moderation.url }
output "queue_arn" { value = aws_sqs_queue.review_moderation.arn }
output "dlq_arn" { value = aws_sqs_queue.dead_letter.arn }
output "state_machine_arn" { value = aws_sfn_state_machine.review_moderation.arn }