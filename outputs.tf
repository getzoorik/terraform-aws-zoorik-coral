output "role_arn" {
  description = "ARN of the agent's role. With IRSA it is the service account annotation eks.amazonaws.com/role-arn; with EKS Pod Identity the association hands it to the agent."
  value       = aws_iam_role.agent.arn
}
