# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 — Solution Architecture

EKS 기반 MSA + ZTNA 인프라를 **Terraform / eksctl / Kubernetes manifest** 로 구성한 결과물입니다.
모든 리소스는 서울(`ap-northeast-2`) 리전 기준입니다.

## 디렉토리 구조

```
terraform/                 # AWS 인프라 (VPC, Bastion, S3, ECR, DynamoDB, Lambda, ALB, CloudFront, WAF, KMS, IAM)
  ├─ versions.tf  variables.tf  data.tf
  ├─ kms.tf  vpc.tf  endpoints.tf
  ├─ bastion.tf  s3.tf  ecr.tf  dynamodb.tf
  ├─ lambda.tf  lambda/index.py  alb.tf
  ├─ cloudfront.tf  waf.tf  cloudwatch.tf
  ├─ iam.tf  outputs.tf
  └─ assets/static/        # ← 제공된 정적 배포 파일을 여기에 배치
eksctl/
  └─ cluster.yaml          # EKS 클러스터 + 3개 Managed NodeGroup
k8s/
  ├─ 00-namespaces.yaml  01-coredns-wsc-local.yaml  02-storageclass.yaml
  ├─ app/                 # ConfigMap, Deployment, Service, PDB, TargetGroupBinding
  ├─ monitoring/          # Prometheus/Grafana helm values, dashboard, addon-ingress
  └─ logging/             # Fluent Bit DaemonSet
app/
  └─ Dockerfile           # 제공된 Go binary "book" 경량 이미지(<8MB, curl 포함)
```

## 배포 순서

### 1) Terraform (네트워크 + AWS 리소스)

```bash
cd terraform
# 제공된 정적 파일을 assets/static/ 에 복사한 뒤
terraform init
terraform apply
terraform output            # 아래 단계에서 사용할 값 확인
```

주요 output: `account_id`, `vpc_id`, `workload_subnet_ids`, `eks_kms_key_arn`,
`ecr_repository_url`, `app_target_group_arn`, `cloudfront_domain`, `bastion_public_ip`.

### 2) 컨테이너 이미지 빌드 & ECR push (Bastion 에서)

```bash
# 제공된 Go binary 를 app/book 로 배치
cd app
ECR=$(cd ../terraform && terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build --platform linux/amd64 -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"
docker images "$ECR:v1.0.0"   # 8MB 이하인지 확인 (초과 시 UPX 압축 강화)
```

### 3) EKS 클러스터 (eksctl)

`cluster.yaml` 의 placeholder 를 terraform output 으로 치환 후 생성:

```bash
cd eksctl
ACCOUNT_ID=$(cd ../terraform && terraform output -raw account_id)
EKS_KMS=$(cd ../terraform && terraform output -raw eks_kms_key_arn)
VPC_ID=$(cd ../terraform && terraform output -raw vpc_id)
WL_A=$(cd ../terraform && terraform output -json workload_subnet_ids | jq -r '."wsc-workload-a"')
WL_C=$(cd ../terraform && terraform output -json workload_subnet_ids | jq -r '."wsc-workload-c"')

sed -e "s|<ACCOUNT_ID>|$ACCOUNT_ID|g" \
    -e "s|<EKS_KMS_KEY_ARN>|$EKS_KMS|g" \
    -e "s|<VPC_ID>|$VPC_ID|g" \
    -e "s|<WORKLOAD_A_ID>|$WL_A|g" \
    -e "s|<WORKLOAD_C_ID>|$WL_C|g" \
    cluster.yaml > cluster.rendered.yaml

eksctl create cluster -f cluster.rendered.yaml

      # Kubernetes 내부 도메인 *.cluster.local -> *.wsc.local (CoreDNS 패치와 짝)
      # AL2023 nodeadm/kubelet 이 --config-dir 의 drop-in 을 병합한다. (AL2 의 /etc/eks/kubelet-extra-args 는 무시됨)
      - "mkdir -p /etc/kubernetes/kubelet/config.json.d && printf '{\"apiVersion\":\"kubelet.config.k8s.io/v1beta1\",\"kind\":\"KubeletConfiguration\",\"clusterDomain\":\"wsc.local\"}' > /etc/kubernetes/kubelet/config.json.d/20-wsc-clusterdomain.conf"
      # 노드명 <INSTANCE_ID>.ec2.internal
      - "IID=$(curl -s -H \"X-aws-ec2-metadata-token: $(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')\" http://169.254.169.254/latest/meta-data/instance-id); hostnamectl set-hostname ${IID}.ec2.internal"
```

> IRSA 정책(`wsc-app-policy`, `wsc-fluentbit-policy`, `wsc-ebs-csi-kms-policy`)은
> Terraform 이 먼저 생성하므로 2)→3) 순서를 지킵니다.

### 4) AWS Load Balancer Controller (addon NodeGroup 에 배치)

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=wsc-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId="$VPC_ID" \
  --set nodeSelector.type=addon
```

### 5) Kubernetes 리소스

```bash
cd ../k8s
kubectl apply -f 00-namespaces.yaml

# 내부 도메인 wsc.local 적용
kubectl apply -f 01-coredns-wsc-local.yaml
kubectl -n kube-system rollout restart deploy/coredns

# StorageClass (KMS arn 치환)
sed "s|<EKS_KMS_KEY_ARN>|$EKS_KMS|g" 02-storageclass.yaml | kubectl apply -f -

# App (ECR / TargetGroup ARN 치환)
ECR=$(cd ../terraform && terraform output -raw ecr_repository_url)
TG=$(cd ../terraform && terraform output -raw app_target_group_arn)
kubectl apply -f app/configmap.yaml
sed "s|<ECR_REPOSITORY_URL>|$ECR|g" app/deployment.yaml | kubectl apply -f -
kubectl apply -f app/service.yaml -f app/pdb.yaml
sed "s|<APP_TARGET_GROUP_ARN>|$TG|g" app/targetgroupbinding.yaml | kubectl apply -f -
```

### 6) 모니터링 (Prometheus + Grafana)

```bash
kubectl apply -f monitoring/pvc.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update

helm upgrade --install prometheus prometheus-community/prometheus \
  -n monitoring -f monitoring/prometheus-values.yaml

kubectl -n monitoring create configmap wsc-dashboard --from-file=dashboard.json=monitoring/dashboard.json
helm upgrade --install grafana grafana/grafana -n monitoring -f monitoring/grafana-values.yaml

kubectl apply -f monitoring/addon-ingress.yaml   # wsc-addon-lb (public)
```

### 7) 로깅 (Fluent Bit)

```bash
kubectl apply -f logging/fluent-bit.yaml
```

## 요구사항 ↔ 구현 매핑

| # | 요구사항 | 구현 |
|---|---------|------|
| 4 | VPC, Workload RTB 규칙 없음, Endpoint | `vpc.tf`(workload RTB 라우트 미생성) + `endpoints.tf`(Interface Endpoint only) |
| 5 | Bastion (SSH password, EIP, Admin) | `bastion.tf` |
| 6 | S3 wsc-static-<ACCOUNT_ID> SSE-KMS, /static | `s3.tf` |
| 7 | ECR wsc-repo, KMS+스캔, <8MB, curl | `ecr.tf` + `app/Dockerfile` |
| 8 | DynamoDB wsc-table CMK | `dynamodb.tf` |
| 9 | EKS 1.35, private-only, KMS secret, CW 로그, 3 NodeGroup | `eksctl/cluster.yaml` |
| 9.2 | 노드명/`wsc.local` 도메인, SSH, curl/ping, EBS KMS | `cluster.yaml` preBootstrap + `01-coredns-wsc-local.yaml` |
| 9.3 | Deployment wsc-deploy / wsc-cnt, HA | `app/deployment.yaml`, `app/pdb.yaml` |
| 9.4 | Pod IRSA, 노드 IAM 차단 | `wsc-sa`(eksctl) + IMDS hop limit + `AWS_EC2_METADATA_DISABLED` |
| 9.5 | ConfigMap wsc-config | `app/configmap.yaml` |
| 9.6 | StorageClass wsc-sc, PVC, CMK | `02-storageclass.yaml`, `monitoring/pvc.yaml` |
| 10 | Prometheus/Grafana, 대시보드 | `monitoring/` |
| 11 | Fluent Bit → CloudWatch(/wsc/pod/log), /health 제외, KMS | `logging/fluent-bit.yaml` + `cloudwatch.tf` |
| 12.1 | app-lb internal, 403/404, CloudFront-only | `alb.tf` |
| 12.2 | addon-lb public /grafana /prometheus | `monitoring/addon-ingress.yaml` |
| 13 | WAF POST body admin/sysop block | `waf.tf` |
| 14 | CloudFront S3+ALB origin, HTTPS 리다이렉트, IPv6 off | `cloudfront.tf` |
| 15 | Lambda GET /v1/book, 404 처리 | `lambda.tf` + `lambda/index.py` |

## 검증용 데이터 시드 (예시)

```bash
aws dynamodb put-item --table-name wsc-table --region ap-northeast-2 --item '{
  "client_id":{"S":"C001"},"username":{"S":"Alice"},
  "email":{"S":"kim@example.com"},"concert_name":{"S":"Seoul2025"},
  "booking_id":{"S":"6WVB5S9G"}}'

CF=$(cd terraform && terraform output -raw cloudfront_domain)
curl -s "https://$CF/v1/book?client_id=C001"      # Lambda → 200
curl -s -X POST "https://$CF/v1/book" -d '{"client_id":"C002","username":"Bob","email":"b@e.com","concert_name":"Busan2025"}'  # 앱 → booking_id
curl -si "https://$CF/health"                      # 403 Restrict access to api
```

## 주의 / 검증 필요 포인트

- **노드명 `<INSTANCE_ID>.ec2.internal` 과 `wsc.local` 도메인**: `cluster.yaml` 의
  `preBootstrapCommands` + CoreDNS 패치 + kubelet `--cluster-domain=wsc.local` 조합으로
  적용합니다. AL2023(nodeadm) 환경에 따라 kubelet 인자 주입 방식 조정이 필요할 수 있습니다.
- **CloudFront → 내부 ALB**: CloudFront **VPC Origin** 기능을 사용합니다(`aws_cloudfront_vpc_origin`).
  ALB SG 는 CloudFront origin-facing 관리형 prefix list 만 허용합니다.
- **Grafana 대시보드 PromQL**: nodegroup label join(`kube_node_labels`)을 사용하므로 실제 클러스터
  라벨 기준으로 검증/미세조정 권장.
- **이미지 8MB**: Go 바이너리 크기에 따라 UPX 압축 강도 조정이 필요할 수 있습니다.
