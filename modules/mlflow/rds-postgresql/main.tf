resource "aws_db_subnet_group" "mlflow_db_subnet_group" {
  name       = var.subnet_group_name
  subnet_ids = var.subnet_ids

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_security_group" "mlflow_rds_postgresql" {
  name   = var.rds_postgresql_security_group
  vpc_id = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    description     = "PostgreSQL from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_db_instance" "mlflow_rds_postgresql" {
  identifier                 = var.identifier_rds_postgresql
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = "db.t3.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  auto_minor_version_upgrade = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.mlflow_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.mlflow_rds_postgresql.id]

  skip_final_snapshot     = true
  backup_retention_period = 1
  deletion_protection     = false

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "mlflow"
  }
}
