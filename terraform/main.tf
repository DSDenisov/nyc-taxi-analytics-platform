terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "raw_zone" {
  bucket = var.raw_bucket_name

  tags = {
    Project = var.project_name
    Environment = var.environment
    Purpose = "raw-landing-zone"
  }
}

resource "aws_s3_bucket_versioning" "raw_zone" {
  bucket = aws_s3_bucket.raw_zone.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_zone" {
  bucket = aws_s3_bucket.raw_zone.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_zone" {
  bucket = aws_s3_bucket.raw_zone.id

  block_public_acls         = true
  block_public_policy       = true
  ignore_public_acls        = true
  restrict_public_buckets   = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_zone" {
  bucket = aws_s3_bucket.raw_zone.id

  rule {
    id = "expire-old-version"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "expire-temp-uploads"
    status = "Enabled"

    filter {
      prefix = "_tmp/"
    }

    expiration {
      days = 1
    }
  }
}

resource "aws_iam_user" "ingestion" {
  name = "nyc-taxi-ingestion-user"
  tags = {
    Project = var.project_name
    Environment = var.environment
    Purpose = "raw-data-ingestion"
  }
}

resource "aws_iam_policy" "ingestion_s3_access" {
  name        = "nyc-taxi-ingestion-s3-policy"
  description = "Least-privilege access for ingestion script to write/read/list the raw landing zone bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid     = "AllowPutAndListForIngestion"
        Effect  = "Allow"
        Action  = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_zone.arn,
          "${aws_s3_bucket.raw_zone.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ingestion_attach" {
  user        = aws_iam_user.ingestion.name
  policy_arn  = aws_iam_policy.ingestion_s3_access.arn
}


