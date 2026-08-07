variable "region_name" { type = string }
variable "review_table_name" { type = string }
variable "review_table_arn" { type = string }
variable "moderation_events_table_name" { type = string }
variable "moderation_events_table_arn" { type = string }
variable "quarantine_bucket_name" { type = string }
variable "quarantine_bucket_arn" { type = string }
variable "public_review_bucket_name" { type = string }
variable "public_review_bucket_arn" { type = string }
variable "public_review_bucket_domain" { type = string }
variable "toxicity_threshold" {
  type    = number
  default = 0.70
}

variable "image_confidence_threshold" {
  type    = number
  default = 70
}
