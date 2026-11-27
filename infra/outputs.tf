output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "aurora_cluster_id" {
  value = aws_rds_cluster.aurora.cluster_identifier
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "opensearch_endpoint" {
  value = aws_opensearch_domain.logs.endpoint
}

output "opensearch_domain" {
  value = aws_opensearch_domain.logs.domain_name
}

output "dynamodb_table" {
  value = aws_dynamodb_table.audit.name
}

output "fluent_bit_role_arn" {
  value = aws_iam_role.fluent_bit.arn
}
