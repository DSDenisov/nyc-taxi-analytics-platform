output "raw_bucket_name" {
  description = "Name of the s3 raw landing zone bucket"
  value = aws_s3_bucket.raw_zone.id
}

output "raw_bucket_arn" {
  description = "ARN of the s3 raw landing zone bucket"
  value = aws_s3_bucket.raw_zone.arn
}

output "ingestion_user_arn" {
  description = "ARN oth the IAM user used by the ingestion script"
  value = aws_iam_user.ingestion.arn
}

output "ingestion_policy_arn" {
  description = "ARN of the least-privilege s3 policy attached to the ingestion user"
  value = aws_iam_policy.ingestion_s3_access.arn
}