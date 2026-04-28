# Security Group for Monitoring Stack (Nagios & Grafana)
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Security group for Nagios and Grafana monitoring instances"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-monitoring-sg"
    }
  )
}

# Nagios HTTP (port 80)
resource "aws_security_group_rule" "nagios_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Restrict to VPC - change to your IP/CIDR in production
  security_group_id = aws_security_group.monitoring.id
  description       = "HTTP access to Nagios"
}

# Nagios HTTPS (port 443)
resource "aws_security_group_rule" "nagios_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Restrict to VPC - change to your IP/CIDR in production
  security_group_id = aws_security_group.monitoring.id
  description       = "HTTPS access to Nagios"
}

# Nagios NRPE (port 5667) - for agent communication
resource "aws_security_group_rule" "nagios_nrpe" {
  type              = "ingress"
  from_port         = 5667
  to_port           = 5667
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Allow from VPC
  security_group_id = aws_security_group.monitoring.id
  description       = "NRPE for remote checks"
}

# Grafana HTTP (port 3000)
resource "aws_security_group_rule" "grafana_http" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Restrict to VPC - change to your IP/CIDR in production
  security_group_id = aws_security_group.monitoring.id
  description       = "HTTP access to Grafana"
}

# Grafana HTTPS (port 443)
resource "aws_security_group_rule" "grafana_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Restrict to VPC
  security_group_id = aws_security_group.monitoring.id
  description       = "HTTPS access to Grafana"
}

# SSH access (port 22) from VPC
resource "aws_security_group_rule" "monitoring_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Restrict to VPC - change to your IP/CIDR in production
  security_group_id = aws_security_group.monitoring.id
  description       = "SSH access to monitoring instances"
}

# Allow all outbound traffic from monitoring
resource "aws_security_group_rule" "monitoring_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow all outbound traffic"
}

# Security Group for Target Instances
resource "aws_security_group" "target_instances" {
  name        = "${var.project_name}-target-sg"
  description = "Security group for target EC2 instances to be healed"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-target-sg"
    }
  )
}

# SSH access to target instances (from VPC)
resource "aws_security_group_rule" "target_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.target_instances.id
  description       = "SSH access to target instances"
}

# HTTP access to target instances (from monitoring)
resource "aws_security_group_rule" "target_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  security_group_id        = aws_security_group.target_instances.id
  description              = "HTTP from monitoring"
}

# HTTPS access to target instances (from monitoring)
resource "aws_security_group_rule" "target_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  security_group_id        = aws_security_group.target_instances.id
  description              = "HTTPS from monitoring"
}

# NRPE for Nagios checks (from monitoring)
resource "aws_security_group_rule" "target_nrpe" {
  type                     = "ingress"
  from_port                = 5667
  to_port                  = 5667
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  security_group_id        = aws_security_group.target_instances.id
  description              = "NRPE from Nagios"
}

# Custom application port (if needed)
resource "aws_security_group_rule" "target_custom_app" {
  type              = "ingress"
  from_port         = 8000
  to_port           = 8099
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.target_instances.id
  description       = "Custom application ports"
}

# Allow all outbound traffic from target instances
resource "aws_security_group_rule" "target_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.target_instances.id
  description       = "Allow all outbound traffic"
}

# Allow target instances to communicate with each other
resource "aws_security_group_rule" "target_self_communication" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.target_instances.id
  description       = "Allow communication between target instances"
}

# Security Group for Lambda function (if deployed in VPC)
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda function if deployed in VPC"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-sg"
    }
  )
}

# Allow Lambda to communicate with target instances (SSM)
resource "aws_security_group_rule" "lambda_ssm_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_sg.id
  description       = "Allow outbound for SSM communication"
}
