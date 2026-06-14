# ---------------------------------------------------------------------------
# Bastion (요구사항 5)
# - Public Subnet 배치, EIP 로 재시작 시에도 IP 고정
# - SSH(22) 만 허용
# - SSH Password 방식(Skill53##), Admin 권한(AdministratorAccess) IAM Role
# - 패키지: awscliv2, jq, curl, ping, kubectl, eksctl
# - Tag: Name=wsc-bastion
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "wsc-bastion-sg"
  description = "Bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 유의사항 6: 80/443 Outbound Anyopen + 전체 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-bastion-sg" }
}

# ----- Admin 권한 IAM Role -----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "wsc-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "wsc-bastion-profile"
  role = aws_iam_role.bastion.name
}

# ----- EIP -----
resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "wsc-bastion-eip" }
}

# ----- User Data: 패키지 설치 + SSH Password 설정 -----
locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf -y update
    dnf -y install jq tar gzip iputils bind-utils git

    # awscli v2
    curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    cd /tmp && unzip -q awscliv2.zip && ./aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip

    # kubectl (EKS 1.35 대응)
    curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl

    # eksctl
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl /usr/local/bin/

    # helm (Prometheus/Grafana/LB Controller 설치용)
    curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # SSH Password 인증 활성화 + 패스워드 설정
    echo 'ec2-user:${var.ssh_password}' | chpasswd
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    echo 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/60-wsc.conf
    systemctl restart sshd

    # kubeconfig 자동 구성
    su - ec2-user -c "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}" || true
  EOF
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this[local.public_subnet_keys[0]].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = local.bastion_user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 강제
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wsc-bastion" }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
