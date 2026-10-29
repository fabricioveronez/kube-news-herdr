output "region" { value = var.region }
output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "private_subnet_ids" { value = module.network.private_subnet_ids }
output "database_subnet_ids" { value = module.network.database_subnet_ids }
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_version" { value = module.eks.cluster_version }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
output "rds_endpoint" { value = module.rds.endpoint }
output "rds_port" { value = module.rds.port }
output "db_name" { value = module.rds.db_name }
output "db_username" { value = module.rds.username }
