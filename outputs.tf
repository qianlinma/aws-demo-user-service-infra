output "user_service_alb_dns_name" {
  description = "Internal ALB DNS name that product service can call later."
  value       = aws_lb.user_service.dns_name
}

output "user_service_ecr_repository_url" {
  description = "ECR repository URL for the user service image."
  value       = aws_ecr_repository.user_service.repository_url
}

output "users_table_name" {
  description = "DynamoDB table used by the user service."
  value       = aws_dynamodb_table.users.name
}
