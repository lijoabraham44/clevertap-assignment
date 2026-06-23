terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }

  backend "s3" {
    bucket         = "clevertap-tfstate-prod-111122223333"
    key            = "prod/ap-south-1/platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "clevertap-tflock-prod"
    encrypt        = true
  }
}
