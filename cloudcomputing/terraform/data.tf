data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Bastion / NodeGroup 용 Amazon Linux 2023 AMI (x86_64)
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "wsc-static-${data.aws_caller_identity.current.account_id}"

  public_subnet_keys   = [for k, v in var.subnets : k if v.tier == "public"]
  private_subnet_keys  = [for k, v in var.subnets : k if v.tier == "private"]
  workload_subnet_keys = [for k, v in var.subnets : k if v.tier == "workload"]
}
