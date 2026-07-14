module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"
  attach_cluster_encryption_policy = false
  cluster_enabled_log_types = []
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = true
  cluster_name = var.cluster_name
  cluster_version = var.cluster_version
  create_cloudwatch_log_group = false

  # The aws-auth ConfigMap is no longer managed by the module in v20+; access
  # is managed via EKS access entries. Grant the identity running Terraform
  # (the control node) cluster admin so the subsequent update-kubeconfig and
  # workload deploy (kubectl/helm) are authorized. Managed node group roles
  # get access entries automatically.
  enable_cluster_creator_admin_permissions = true

  vpc_id = var.vpc_id
  subnet_ids = var.subnet_ids

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol = "-1"
      from_port = 1
      to_port = 65535
      type = "ingress"
      self = true
    }
    user_ports_incoming_node = {
      description = "Incoming TCP to user ports"
      protocol = "tcp"
      from_port = 32001
      to_port = 33999
      type = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  cluster_security_group_additional_rules = {
    user_ports_incoming_cluster = {
      description = "Incoming TCP to user ports"
      protocol = "tcp"
      from_port = 32001
      to_port = 33999
      type = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    main = {
      min_size = 2
      max_size = 2
      desired_size = 2
      # AWS-managed EKS-optimized AL2023 AMI (nodeadm bootstrap). GPU nodes use
      # the NVIDIA-optimized variant (drivers preinstalled); requires a GPU
      # instance type via ICL_AWS_INSTANCE_TYPE.
      ami_type = var.gpu_type == "nvidia" ? "AL2023_x86_64_NVIDIA" : "AL2023_x86_64_STANDARD"
      instance_types = ["${var.instance_type}"]
      capacity_type  = "ON_DEMAND"
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs         = {
            volume_size           = 250
            volume_type           = "gp3"
            encrypted             = false
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = {
    "ICL/Cluster" = var.cluster_name
    ManagedBy = "Terraform"
  }
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.9.2"

  role_name = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    "ICL/Cluster" = var.cluster_name
    ManagedBy = "Terraform"
  }
}
