variable "aws_region" {
    type = string
    nullable = false
    default = "us-east-2"
}

variable "aws_account_id" {
    description = "AWS Account ID"
    type = string
    nullable = false
}

variable "aws_access_key_id" {
    description = "AWS API Key"
    type        = string
    nullable    = false
}

variable "aws_secret_access_key" {
    description = "AWS API Secret"
    type        = string
    sensitive   = true
    nullable    = false
}

variable "aws_session_token" {
    description = "AWS Session Token"
    type        = string
    sensitive   = true
    nullable    = false
}

variable "aws_ami" {
    description = "Instance AMI for jump server"
    type        = string
    nullable    = false
    default     = "ami-0490fddec0cbeb88b" # Amazon Linux 2 for US-East-2
}

variable "aws_instancesize" {
    description = "Instance size for jump server"
    type        = string
    nullable    = false
    default     = "t3.medium"
}

variable "existing_key_pair_name" {
  description = "The name of the existing EC2 Key Pair in your AWS account."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the private key file corresponding to existing_key_pair_name"
  type        = string
}

variable "cflt_managed_by" {
  description = "Tag value for cflt_managed_by"
  type        = string
}

variable "cflt_managed_id" {
  description = "Tag value for cflt_managed_id"
  type        = string
}

variable "cflt_keep_until" {
  description = "Tag value for cflt_keep_until"
  type        = string
  default     = "2025-12-31"
}
