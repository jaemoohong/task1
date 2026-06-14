# ---------------------------------------------------------------------------
# CloudWatch Logs (요구사항 11)
# Fluent Bit 가 사용할 로그 그룹을 KMS 암호화하여 미리 생성한다.
# (Fluent Bit 는 auto_create_group=false 로 이 그룹에 기록)
# EKS Control Plane 로그 그룹(/aws/eks/...)도 eksctl 이 생성하지만,
# 해당 그룹 KMS 암호화는 필요 시 콘솔/CLI 로 추가 적용한다.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "wsc_pod_log" {
  name              = "/wsc/pod/log"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn

  tags = { Name = "wsc-pod-log" }
}
