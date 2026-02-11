resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_security_group" "node" {
  name_prefix = "${var.cluster_name}-node-"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "node_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.node.id
  security_group_id        = aws_security_group.node.id
  description              = "Node to node communication"
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.node.id
  description              = "Cluster to node communication"
}

resource "aws_security_group_rule" "node_ingress_gateway" {
  type              = "ingress"
  from_port         = var.gateway_port
  to_port           = var.gateway_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
  description       = "OpenClaw gateway port"
}
