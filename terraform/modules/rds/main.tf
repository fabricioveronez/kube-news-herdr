resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-database"
  subnet_ids = var.database_subnet_ids
  tags       = { Name = "${var.project_name}-database" }
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-database"
  description = "PostgreSQL access from the EKS cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-database" }
}

resource "aws_db_instance" "this" {
  identifier                 = "${var.project_name}-postgres"
  engine                     = "postgres"
  engine_version             = var.db_engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  multi_az                   = var.db_multi_az
  publicly_accessible        = false
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [aws_security_group.database.id]
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = var.db_password
  port                       = 5432
  backup_retention_period    = 7
  skip_final_snapshot        = var.db_skip_final_snapshot
  final_snapshot_identifier  = var.db_skip_final_snapshot ? null : "${var.project_name}-postgres-final"
  deletion_protection        = var.db_deletion_protection
  apply_immediately          = true

  tags = { Name = "${var.project_name}-postgres" }
}
