/************************************************************
alb
************************************************************/
resource "aws_lb" "app" {
  name               = "alb-${var.env}"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [var.alb.security_group_id]
  subnets            = [var.alb.subnet_id_1a, var.alb.subnet_id_1c]
  idle_timeout       = 120
}

/************************************************************
target group
************************************************************/
resource "aws_lb_target_group" "app" {
  name             = "app-${var.env}"
  vpc_id           = var.vpc_id
  port             = 3000
  protocol         = "HTTP"
  target_type      = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/up"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

/************************************************************
listeners
************************************************************/
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
