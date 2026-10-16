output "agent_role_arn" {
  description = "The agent's role, handed to it by EKS Pod Identity."
  value       = module.zoorik_coral.role_arn
}

output "cluster_resource_id" {
  description = "The agent's clusterResourceId."
  value       = data.aws_eks_cluster.this.arn
}
