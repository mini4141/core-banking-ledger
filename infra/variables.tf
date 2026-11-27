variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "aws_profile" {
  type    = string
  default = "core-banking-ledger-deployer"
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "aurora_engine_version" {
  type    = string
  default = "8.0.mysql_aurora.3.12.0"
}

variable "deployer_cidr" {
  description = "Deployer public IP as /32, allowed to reach OpenSearch Dashboards (passed by scripts/deploy.sh)"
  type        = string
}
