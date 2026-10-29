module "network" {
  source             = "./modules/network"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "eks" {
  source                       = "./modules/eks"
  project_name                 = var.project_name
  private_subnet_ids           = module.network.private_subnet_ids
  kubernetes_version           = var.kubernetes_version
  cluster_public_access_cidrs  = var.cluster_public_access_cidrs
  cluster_admin_principal_arns = var.cluster_admin_principal_arns
  node_instance_types          = var.node_instance_types
  node_desired_size            = var.node_desired_size
  node_min_size                = var.node_min_size
  node_max_size                = var.node_max_size
}

module "rds" {
  source                    = "./modules/rds"
  project_name              = var.project_name
  vpc_id                    = module.network.vpc_id
  database_subnet_ids       = module.network.database_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  db_engine_version         = var.db_engine_version
  db_instance_class         = var.db_instance_class
  db_allocated_storage      = var.db_allocated_storage
  db_multi_az               = var.db_multi_az
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  db_skip_final_snapshot    = var.db_skip_final_snapshot
  db_deletion_protection    = var.db_deletion_protection
}
