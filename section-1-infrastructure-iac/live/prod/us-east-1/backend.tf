terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }

  # State is isolated per account + region + stack. See docs/1b for the rationale.
  # Replace the bucket/account id with the value output by live/bootstrap.
  backend "s3" {
    bucket         = "clevertap-tfstate-prod-111122223333"
    key            = "prod/us-east-1/platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "clevertap-tflock-prod"
    encrypt        = true
  }
}
