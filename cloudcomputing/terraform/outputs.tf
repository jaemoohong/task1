output "account_id" {
  value = local.account_id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "workload_subnet_ids" {
  description = "EKS NodeGroup 이 배치될 Workload Subnet"
  value       = { for k in local.workload_subnet_keys : k => aws_subnet.this[k].id }
}

output "private_subnet_ids" {
  value = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "public_subnet_ids" {
  value = { for k in local.public_subnet_keys : k => aws_subnet.this[k].id }
}

output "eks_kms_key_arn" {
  description = "EKS Secret/EBS 암호화 CMK (eksctl secretsEncryption.keyARN 에 사용)"
  value       = aws_kms_key.eks.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.repo.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.id
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "app_target_group_arn" {
  description = "k8s TargetGroupBinding 이 Pod IP 를 등록할 대상 (app-lb)"
  value       = aws_lb_target_group.app.arn
}

# eksctl iamserviceaccount.attachPolicyARNs 에 사용할 정책 ARN
output "iam_policy_arns" {
  value = {
    app       = aws_iam_policy.app.arn
    fluentbit = aws_iam_policy.fluentbit.arn
    ebs_csi   = aws_iam_policy.ebs_csi_kms.arn
  }
}
