module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "bennybe-eks-vpc"
  cidr                 = var.cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = [local.subnet_cidr1, local.subnet_cidr2, local.subnet_cidr3]
  public_subnets       = [local.pub_subnet_cidr]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}