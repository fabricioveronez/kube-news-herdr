variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "database_subnet_ids" { type = list(string) }
variable "cluster_security_group_id" { type = string }
variable "db_engine_version" { type = string }
variable "db_instance_class" { type = string }
variable "db_allocated_storage" { type = number }
variable "db_multi_az" { type = bool }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "db_password" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128 && length(regexall("[/@\" ]", var.db_password)) == 0
    error_message = "The database password must be 8-128 characters and cannot contain /, @, double quotes, or spaces."
  }
}
variable "db_skip_final_snapshot" { type = bool }
variable "db_deletion_protection" { type = bool }
