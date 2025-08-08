terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "5.89.0"
        }
    }
}

provider "aws" {
    region          = var.aws_region
    access_key      = var.aws_access_key_id
    secret_key      = var.aws_secret_access_key
    token           = var.aws_session_token
}

# Random ID to prevent name collision
resource "random_id" "env_display_id" {
    byte_length = 4
}
