variable "region" {
  description = "모든 리소스를 생성할 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "wsc-eks-cluster"
}

variable "cluster_version" {
  description = "EKS 버전"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "wsc-vpc CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

# Reference01 의 서브넷/라우트테이블 정의를 그대로 사용한다.
variable "subnets" {
  description = "서브넷 정의 (Reference01)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private | workload
  }))
  default = {
    "wsc-public-a"   = { cidr = "10.0.0.0/24", az = "ap-northeast-2a", tier = "public" }
    "wsc-public-c"   = { cidr = "10.0.1.0/24", az = "ap-northeast-2c", tier = "public" }
    "wsc-private-a"  = { cidr = "10.0.2.0/24", az = "ap-northeast-2a", tier = "private" }
    "wsc-private-c"  = { cidr = "10.0.3.0/24", az = "ap-northeast-2c", tier = "private" }
    "wsc-workload-a" = { cidr = "10.0.4.0/24", az = "ap-northeast-2a", tier = "workload" }
    "wsc-workload-c" = { cidr = "10.0.5.0/24", az = "ap-northeast-2c", tier = "workload" }
  }
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_password" {
  description = "Bastion / Node SSH 패스워드 (과제 지정값)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
