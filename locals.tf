locals{
  subnet_cidr1 = cidrsubnets(var.cidr, 2, 2, 2, 2)[0]
  subnet_cidr2 = cidrsubnets(var.cidr, 2, 2, 2, 2)[1]
  subnet_cidr3 = cidrsubnets(var.cidr, 2, 2, 2, 2)[2]
  pub_subnet_cidr = cidrsubnets(var.cidr, 2, 2, 2, 2)[3]
  name            = "ex-${replace(basename(path.cwd), "_", "-")}"
  cluster_version = "1.21"
  region          = var.region

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }

    kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.eks.cluster_id
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.eks.cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}
