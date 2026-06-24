variable "aws_region" {
  description = "AWS region where user service resources will be created."
  type        = string
}

variable "aws_profile" {
  description = "Local AWS CLI profile used by Terraform."
  type        = string
}

variable "github_connection_arn" {
  description = "Existing AWS CodeConnections ARN for GitHub."
  type        = string
  default     = "arn:aws:codeconnections:us-west-2:123316866274:connection/9101b154-eacf-484f-9b70-fa3d7486384b"
}

variable "github_repository_id" {
  description = "GitHub repository for the user service source code."
  type        = string
  default     = "qianlinma/aws-demo-user-service-backend"
}

variable "github_branch_name" {
  description = "Git branch watched by the user service pipeline."
  type        = string
  default     = "main"
}

variable "vpc_name" {
  description = "Existing demo VPC Name tag."
  type        = string
  default     = "demo-vpc-tf"
}

variable "private_subnet_name_prefix" {
  description = "Existing private subnet Name tag prefix."
  type        = string
  default     = "demo-backend-private-subnet-"
}

variable "ecs_cluster_name" {
  description = "Existing ECS cluster name."
  type        = string
  default     = "demo-cluster-tf"
}

variable "backend_task_security_group_name" {
  description = "Existing product/backend ECS task security group allowed to call the user service."
  type        = string
  default     = "demo-backend-ecs-task-sg-tf"
}

variable "user_ecr_repository_name" {
  description = "ECR repository name for the user service image."
  type        = string
  default     = "demo-user-service-tf"
}

variable "users_table_name" {
  description = "DynamoDB table name for demo users."
  type        = string
  default     = "demo-users-tf"
}

variable "user_container_name" {
  description = "ECS container name for the user service."
  type        = string
  default     = "demo-user-service"
}

variable "user_container_port" {
  description = "Spring Boot container port."
  type        = number
  default     = 8080
}

variable "service_discovery_namespace_name" {
  description = "Private DNS namespace used by Cloud Map service discovery."
  type        = string
  default     = "demo.internal"
}

variable "user_service_discovery_name" {
  description = "Cloud Map service name for the user service."
  type        = string
  default     = "user"
}
