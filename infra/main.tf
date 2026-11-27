terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.100" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "core-banking-ledger"
      Ephemeral = "true"
      ManagedBy = "terraform"
      Owner     = "alvieirvansyah"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name = "core-banking-ledger"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

# --- network: no NAT gateway. Nodes sit in public subnets, databases in isolated subnets. ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = local.name
  cidr = "10.20.0.0/16"
  azs  = local.azs

  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24"]
  database_subnets = ["10.20.10.0/24", "10.20.11.0/24"]

  enable_nat_gateway                 = false
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  map_public_ip_on_launch            = true
  enable_dns_hostnames               = true
  enable_dns_support                 = true

  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
}

# --- EKS: 2x t3.large SPOT ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  create_kms_key                           = false
  cluster_encryption_config                = {}
  cluster_enabled_log_types                = []
  create_cloudwatch_log_group              = false

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    spot = {
      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      min_size       = 2
      max_size       = 2
      desired_size   = 2
      subnet_ids     = module.vpc.public_subnets
    }
  }
}

# --- ECR (force-deletable) ---
resource "aws_ecr_repository" "app" {
  for_each             = toset(["accounts-service", "transfer-service", "audit-service", "ops-console"])
  name                 = "core-banking/${each.key}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"
}

# --- Aurora MySQL Serverless v2, private, reachable only from the EKS nodes ---
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_security_group" "aurora" {
  name_prefix = "${local.name}-aurora-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL from EKS nodes only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = local.name
  engine                  = "aurora-mysql"
  engine_version          = var.aurora_engine_version
  database_name           = "accounts"
  master_username         = "ledger"
  master_password         = random_password.db.result
  db_subnet_group_name    = module.vpc.database_subnet_group_name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}

# --- DynamoDB audit table (on-demand) ---
resource "aws_dynamodb_table" "audit" {
  name         = "audit_events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
}

# --- IAM via EKS Pod Identity ---
data "aws_iam_policy_document" "pods_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "audit" {
  name               = "${local.name}-audit-service"
  assume_role_policy = data.aws_iam_policy_document.pods_trust.json
}

resource "aws_iam_role_policy" "audit_dynamodb" {
  role = aws_iam_role.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:DescribeTable"]
      Resource = aws_dynamodb_table.audit.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "audit" {
  cluster_name    = module.eks.cluster_name
  namespace       = "core-banking"
  service_account = "audit-service"
  role_arn        = aws_iam_role.audit.arn
}

resource "aws_iam_role" "fluent_bit" {
  name               = "${local.name}-fluent-bit"
  assume_role_policy = data.aws_iam_policy_document.pods_trust.json
}

resource "aws_iam_role_policy" "fluent_bit_opensearch" {
  role = aws_iam_role.fluent_bit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet", "es:ESHttpHead"]
      Resource = "${aws_opensearch_domain.logs.arn}/*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = module.eks.cluster_name
  namespace       = "logging"
  service_account = "fluent-bit"
  role_arn        = aws_iam_role.fluent_bit.arn
}

# --- Amazon OpenSearch Service: one t3.small node, access limited to Fluent Bit's role and the deployer IP ---
resource "aws_opensearch_domain" "logs" {
  domain_name    = local.name
  engine_version = "OpenSearch_2.17"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  encrypt_at_rest { enabled = true }
  node_to_node_encryption { enabled = true }
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.fluent_bit.arn }
        Action    = "es:ESHttp*"
        Resource  = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
      },
      {
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "es:ESHttp*"
        Resource  = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
        Condition = { IpAddress = { "aws:SourceIp" = [var.deployer_cidr] } }
      }
    ]
  })
}
