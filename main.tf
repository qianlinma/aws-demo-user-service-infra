provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "demo" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.demo.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${var.private_subnet_name_prefix}*"]
  }
}

data "aws_ecs_cluster" "demo" {
  cluster_name = var.ecs_cluster_name
}

data "aws_security_group" "backend_task" {
  name   = var.backend_task_security_group_name
  vpc_id = data.aws_vpc.demo.id
}

# 查找已经存在的 Cloud Map private namespace，比如 demo.local。
# User Service 会注册到这个 namespace 下面，形成 user.demo.local。
data "aws_service_discovery_dns_namespace" "demo" {
  name = var.service_discovery_namespace_name
  type = "DNS_PRIVATE"
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_ecr_repository" "user_service" {
  name                 = var.user_ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "demo-user-ecs-task-execution-role-tf"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "demo-user-ecs-task-role-tf"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_dynamodb_table" "users" {
  name         = var.users_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "N"
  }
}

resource "aws_dynamodb_table_item" "user_1" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    id              = { N = "1" }
    name            = { S = "Alice Chen" }
    membershipLevel = { S = "GOLD" }
    region          = { S = "us-west" }
  })
}

resource "aws_dynamodb_table_item" "user_2" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    id              = { N = "2" }
    name            = { S = "Ben Carter" }
    membershipLevel = { S = "SILVER" }
    region          = { S = "us-east" }
  })
}

resource "aws_dynamodb_table_item" "user_3" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    id              = { N = "3" }
    name            = { S = "Maya Singh" }
    membershipLevel = { S = "PLATINUM" }
    region          = { S = "eu-central" }
  })
}

resource "aws_iam_role_policy" "ecs_task_dynamodb_read" {
  name = "demo-users-dynamodb-read-tf"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.users.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "user_service" {
  name              = "/ecs/demo-user-service-tf"
  retention_in_days = 7
}

resource "aws_security_group" "user_alb" {
  name        = "demo-user-alb-sg-tf"
  description = "Allow product backend tasks to call the internal user service ALB"
  vpc_id      = data.aws_vpc.demo.id

  ingress {
    description     = "Allow product service HTTP access to user service"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [data.aws_security_group.backend_task.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "user_task" {
  name        = "demo-user-ecs-task-sg-tf"
  description = "Allow internal user service ALB to reach the user service task"
  vpc_id      = data.aws_vpc.demo.id

  ingress {
    description     = "Allow ALB access to Spring Boot user service"
    from_port       = var.user_container_port
    to_port         = var.user_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.user_alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "user_service" {
  name               = "demo-user-alb-tf"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.user_alb.id]
  subnets            = data.aws_subnets.private.ids
}

resource "aws_lb_target_group" "user_service" {
  name        = "demo-user-tg-tf"
  port        = var.user_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.demo.id

  health_check {
    enabled             = true
    path                = "/status"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "user_http" {
  load_balancer_arn = aws_lb.user_service.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }
}

resource "aws_service_discovery_service" "user" {
  # Cloud Map 里的 service 名字；配合 namespace 会变成 user.demo.local。
  name = var.user_service_discovery_name

  dns_config {
    # 把这个 service 放进 demo.local 这个 VPC 内部 DNS namespace。
    namespace_id   = data.aws_service_discovery_dns_namespace.demo.id
    routing_policy = "MULTIVALUE"

    # A record 表示 DNS 查询会返回 ECS task 的 private IP。
    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    # ECS 会负责注册/注销 task；这里使用 Cloud Map 的自定义健康检查配置。
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "user_service" {
  family                   = "demo-user-task-tf"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = var.user_container_name
      image     = "${aws_ecr_repository.user_service.repository_url}:latest"
      essential = true

      environment = [
        {
          name  = "USERS_TABLE_NAME"
          value = aws_dynamodb_table.users.name
        }
      ]

      portMappings = [
        {
          containerPort = var.user_container_port
          hostPort      = var.user_container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.user_service.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "user_service" {
  depends_on = [aws_lb_listener.user_http]

  name            = "demo-user-service-tf"
  cluster         = data.aws_ecs_cluster.demo.arn
  task_definition = aws_ecs_task_definition.user_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 60

  # 把 user ECS task 注册到 Cloud Map。
  # 注册后，同一个 VPC 内的服务可以用 user.demo.local 找到 user task。
  service_registries {
    registry_arn = aws_service_discovery_service.user.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = var.user_container_name
    container_port   = var.user_container_port
  }

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.user_task.id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}
