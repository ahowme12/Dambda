# ALB 접근 제어 보안 그룹 (API Gateway VPC Link ENI에서 오는 트래픽만 허용)
resource "aws_security_group" "alb_sg" {
  name   = "${var.region_name}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.vpc_link_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.region_name}-alb-sg" }
}

# 애플리케이션 로드밸런서
resource "aws_lb" "main" {
  name               = "${var.region_name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.private_subnet_ids

  tags = { Name = "${var.region_name}-alb" }
}

# ECS로 트래픽을 전달할 대상 그룹
resource "aws_lb_target_group" "main" {
  name        = "${var.region_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

# HTTP 리스너
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
