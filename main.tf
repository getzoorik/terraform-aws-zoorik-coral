data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.region
  account     = data.aws_caller_identity.current.account_id
  cluster_arn = "arn:${local.partition}:eks:${local.region}:${local.account}:cluster/${var.cluster_name}"

  bounded_role_name = "zoorik-agent-${substr(var.cluster_name, 0, 42)}-${substr(sha256(var.cluster_name), 0, 8)}"
  role_name         = coalesce(var.role_name, length("zoorik-agent-${var.cluster_name}") <= 64 ? "zoorik-agent-${var.cluster_name}" : local.bounded_role_name)
  policy_name       = "ZoorikNodeRemoval-${var.cluster_name}-${substr(sha256(lower(local.cluster_arn)), 0, 8)}"

  irsa        = var.irsa_oidc_issuer_url != null
  issuer_host = local.irsa ? trimprefix(var.irsa_oidc_issuer_url, "https://") : ""

  groups      = "arn:${local.partition}:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/*"
  node_groups = "arn:${local.partition}:eks:${local.region}:${local.account}:nodegroup/${var.cluster_name}/*/*"
  owned_group = { "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
  named_group = { "autoscaling:ResourceTag/eks:cluster-name" = var.cluster_name }
  minimum_only = {
    "autoscaling:MinSize"                              = "false"
    "autoscaling:MaxSize"                              = "true"
    "autoscaling:LaunchConfigurationName"              = "true"
    "autoscaling:LaunchTemplateVersionSpecified"       = "true"
    "autoscaling:VPCZoneIdentifiers"                   = "true"
    "autoscaling:InstanceTypes"                        = "true"
    "autoscaling:ImageId"                              = "true"
    "autoscaling:TargetCapacityTypes"                  = "true"
    "autoscaling:CapacityReservationIds"               = "true"
    "autoscaling:CapacityReservationResourceGroupArns" = "true"
  }
  minimum_tags   = { "aws:TagKeys" = ["coral.zoorik.com/original-min", "coral.zoorik.com/lowered-min"] }
  tag_keys_given = { "aws:TagKeys" = "false" }

  statements = [
    {
      Sid      = "DescribeGroupsAndInstances"
      Effect   = "Allow"
      Action   = ["autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeAutoScalingGroups", "ec2:DescribeInstances"]
      Resource = "*"
    },
    {
      Sid      = "ConfirmOwnGrant"
      Effect   = "Allow"
      Action   = "iam:SimulatePrincipalPolicy"
      Resource = aws_iam_role.agent.arn
    },
    {
      Sid       = "TerminateInThisClustersGroups"
      Effect    = "Allow"
      Action    = "autoscaling:TerminateInstanceInAutoScalingGroup"
      Resource  = local.groups
      Condition = { StringEquals = local.owned_group }
    },
    {
      Sid       = "TerminateInThisClustersNodeGroups"
      Effect    = "Allow"
      Action    = "autoscaling:TerminateInstanceInAutoScalingGroup"
      Resource  = local.groups
      Condition = { StringEquals = local.named_group }
    },
    {
      Sid       = "LowerMinimumInThisClustersGroups"
      Effect    = "Allow"
      Action    = "autoscaling:UpdateAutoScalingGroup"
      Resource  = local.groups
      Condition = { StringEquals = local.owned_group, Null = local.minimum_only }
    },
    {
      Sid       = "LowerMinimumInThisClustersNodeGroups"
      Effect    = "Allow"
      Action    = "autoscaling:UpdateAutoScalingGroup"
      Resource  = local.groups
      Condition = { StringEquals = local.named_group, Null = local.minimum_only }
    },
    {
      Sid       = "RecordMinimumOnThisClustersGroups"
      Effect    = "Allow"
      Action    = "autoscaling:CreateOrUpdateTags"
      Resource  = local.groups
      Condition = { StringEquals = local.owned_group, "ForAllValues:StringEquals" = local.minimum_tags, Null = local.tag_keys_given }
    },
    {
      Sid       = "RecordMinimumOnThisClustersNodeGroupsByName"
      Effect    = "Allow"
      Action    = "autoscaling:CreateOrUpdateTags"
      Resource  = local.groups
      Condition = { StringEquals = local.named_group, "ForAllValues:StringEquals" = local.minimum_tags, Null = local.tag_keys_given }
    },
    {
      Sid      = "LowerMinimumOfThisClustersManagedNodeGroups"
      Effect   = "Allow"
      Action   = ["eks:DescribeNodegroup", "eks:UpdateNodegroupConfig"]
      Resource = local.node_groups
    },
    {
      Sid       = "RecordMinimumOnThisClustersManagedNodeGroups"
      Effect    = "Allow"
      Action    = "eks:TagResource"
      Resource  = local.node_groups
      Condition = { "ForAllValues:StringEquals" = local.minimum_tags, Null = local.tag_keys_given }
    },
  ]
}

resource "aws_iam_role" "agent" {
  name = local.role_name
  assume_role_policy = local.irsa ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:${local.partition}:iam::${local.account}:oidc-provider/${local.issuer_host}" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.issuer_host}:sub" = "system:serviceaccount:zoorik-agent:zoorik-agent"
        "${local.issuer_host}:aud" = "sts.amazonaws.com"
      } }
    }]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = {
        "aws:SourceAccount"                         = local.account
        "aws:RequestTag/eks-cluster-arn"            = local.cluster_arn
        "aws:RequestTag/kubernetes-namespace"       = "zoorik-agent"
        "aws:RequestTag/kubernetes-service-account" = "zoorik-agent"
      } }
    }]
  })
  tags = {
    zoorik-cluster = local.cluster_arn
  }
}

resource "aws_iam_role_policy" "node_removal" {
  name = local.policy_name
  role = aws_iam_role.agent.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = slice(local.statements, 0, var.lower_minimums ? 10 : 4)
  })
}

resource "aws_eks_pod_identity_association" "agent" {
  count           = local.irsa ? 0 : 1
  cluster_name    = var.cluster_name
  namespace       = "zoorik-agent"
  service_account = "zoorik-agent"
  role_arn        = aws_iam_role.agent.arn
}
