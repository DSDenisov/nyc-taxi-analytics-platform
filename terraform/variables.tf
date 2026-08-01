variable "aws_region" {
    description = "AWS region where infrastructure will be provisioned"
    type = string
    default = "us-west-2"
}

variable "project_name" {
    description = "Project identifier used for resource naming and tagging"
    type = string
    default = "nyc-taxi-analytics"
}

variable "environment" {
    description = "Deployment environment (dev, test, uat, prod)"
    type = string
    default = "dev" 
}

variable "raw_bucket_name" {
    description = "Globally unique S3 bucket name for raw landing zone"
    type = string
    # no default 
}