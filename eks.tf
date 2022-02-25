resource "aws_launch_template" "external" {
  name_prefix            = "external-eks-ex-"
  description            = "EKS managed node group external launch template"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
  }

  # if you want to use a custom AMI
  # image_id      = var.ami_id

  # If you use a custom AMI, you need to supply via user-data, the bootstrap script as EKS DOESNT merge its managed user-data then
  # you can add more than the minimum code you see in the template, e.g. install SSM agent, see https://github.com/aws/containers-roadmap/issues/593#issuecomment-577181345
  # (optionally you can use https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/cloudinit_config to render the script, example: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/997#issuecomment-705286151)
  # user_data = base64encode(data.template_file.launch_template_userdata.rendered)

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name      = "external_lt"
      CustomTag = "Instance custom tag"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      CustomTag = "Volume custom tag"
    }
  }

  tag_specifications {
    resource_type = "network-interface"

    tags = {
      CustomTag = "EKS example"
    }
  }

  tags = {
    CustomTag = "Launch template custom tag"
  }

  lifecycle {
    create_before_destroy = true
  }
}
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                    = local.name
  cluster_version                 = local.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  create_cloudwatch_log_group = false

    # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }
  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = 50
    instance_types = ["m6i.large", "m5.large"]

    # We are using the IRSA created below for permissions
    iam_role_attach_cni_policy = false
    create_iam_role = true
  }

    eks_managed_node_groups = {
      # Default node group - as provided by AWS EKS
      default_node_group = {
        # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
        # so we need to disable it to use the default template provided by the AWS EKS managed node group service
        create_launch_template = true
        launch_template_name   = ""

        # Remote access cannot be specified with a launch template
        remote_access = {
          ec2_ssh_key               = aws_key_pair.this.key_name
          source_security_group_ids = [aws_security_group.home-ssh.id, aws_security_group.home-https.id]
        }
      }
    bottlerocket_default = {
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      create_launch_template = true
      launch_template_name   = ""

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"
    }
    # Custom AMI, using module provided bootstrap data
    bottlerocket_custom = {
      # Current bottlerocket AMI
      ami_id   = data.aws_ami.eks_default_bottlerocket.image_id
      platform = "bottlerocket"

      # use module user data template to boostrap
      enable_bootstrap_user_data = true
      # this will get added to the template
      bootstrap_extra_args = <<-EOT
      # extra args added
      [settings.kernel]
      lockdown = "integrity"
      [settings.kubernetes.node-labels]
      "label1" = "foo"
      "label2" = "bar"
      [settings.kubernetes.node-taints]
      "dedicated" = "experimental:PreferNoSchedule"
      "special" = "true:NoSchedule"
      EOT
    }

    # Use existing/external launch template
    external_lt = {
      create_launch_template  = false
      launch_template_name    = aws_launch_template.external.name
      launch_template_version = aws_launch_template.external.default_version
    }

    # Use a custom AMI
    custom_ami = {
      ami_type = "AL2_ARM_64"
      # Current default AMI used by managed node groups - pseudo "custom"
      ami_id = data.aws_ami.eks_default_arm.image_id

      # This will ensure the boostrap user data is used to join the node
      # By default, EKS managed node groups will not append bootstrap script;
      # this adds it back in using the default template provided by the module
      # Note: this assumes the AMI provided is an EKS optimized AMI derivative
      enable_bootstrap_user_data = true

      instance_types = ["t4g.medium"]
    }

 # Demo of containerd usage when not specifying a custom AMI ID
    # (merged into user data before EKS MNG provided user data)
    containerd = {
      name = "containerd"

      # See issue https://github.com/awslabs/amazon-eks-ami/issues/844
      pre_bootstrap_user_data = <<-EOT
      #!/bin/bash
      set -ex
      cat <<-EOF > /etc/profile.d/bootstrap.sh
      export CONTAINER_RUNTIME="containerd"
      export USE_MAX_PODS=false
      export KUBELET_EXTRA_ARGS="--max-pods=110"
      EOF
      # Source extra environment variables in bootstrap script
      sed -i '/^set -o errexit/a\\nsource /etc/profile.d/bootstrap.sh' /etc/eks/bootstrap.sh
      EOT
    }

    # Complete
    complete = {
      name            = "complete-eks-mng"
      use_name_prefix = true

      subnet_ids = module.vpc.private_subnets

      min_size     = 1
      max_size     = 7
      desired_size = 1

      ami_id                     = data.aws_ami.eks_default.image_id
      enable_bootstrap_user_data = true
      bootstrap_extra_args       = "--container-runtime containerd --kubelet-extra-args '--max-pods=20'"

      pre_bootstrap_user_data = <<-EOT
      export CONTAINER_RUNTIME="containerd"
      export USE_MAX_PODS=false
      EOT

      post_bootstrap_user_data = <<-EOT
      echo "you are free little kubelet!"
      EOT

      capacity_type        = "SPOT"
      disk_size            = 256
      force_update_version = true
      instance_types       = ["t3.medium", "t3.large"]
      labels = {
        GithubRepo = "terraform-aws-eks"
        GithubOrg  = "terraform-aws-modules"
      }

      taints = [
        {
          key    = "dedicated"
          value  = "gpuGroup"
          effect = "NO_SCHEDULE"
        }
      ]

      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }

      description = "EKS managed node group example launch template"

      ebs_optimized           = true
      vpc_security_group_ids  = [aws_security_group.all_worker_mgmt.id, aws_security_group.home-ssh.id, aws_security_group.home-https.id]
      disable_api_termination = false
      enable_monitoring       = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 75
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      create_iam_role          = true
      iam_role_name            = "eks-managed-node-group-complete-example"
      iam_role_use_name_prefix = false
      iam_role_description     = "EKS managed node group complete example role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }
      iam_role_additional_policies = [
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      ]

      create_security_group          = true
      security_group_name            = "eks-managed-node-group-complete-example"
      security_group_use_name_prefix = false
      security_group_description     = "EKS managed node group complete example security group"
      security_group_rules = {
        phoneOut = {
          description = "Hello CloudFlare"
          protocol    = "udp"
          from_port   = 53
          to_port     = 53
          type        = "egress"
          cidr_blocks = ["1.1.1.1/32"]
        }
        phoneHome = {
          description                   = "Hello cluster"
          protocol                      = "udp"
          from_port                     = 53
          to_port                       = 53
          type                          = "egress"
          source_cluster_security_group = true # bit of reflection lookup
        }
      }
      security_group_tags = {
        Purpose = "Protector of the kubelet"
      }

      tags = {
        ExtraTag = "EKS managed node group complete example"
      }
    }

      #eks_managed_node_groups
    }







 #EKS end
}



resource "null_resource" "patch" {
  triggers = {
    kubeconfig = base64encode(local.kubeconfig)
    cmd_patch  = "kubectl patch configmap/aws-auth --patch \"${module.eks.aws_auth_configmap_yaml}\" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
    command = self.triggers.cmd_patch
  }
}