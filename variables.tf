variable "cluster_name" {
  description = "Name of the EKS cluster, in the provider's account and region."
  type        = string
}

variable "lower_minimums" {
  description = "Let the agent lower an Auto Scaling group's or managed node group's minimum size when that minimum alone keeps a node it has emptied, and record the old minimum in two tags. Off gives the policy that only terminates drained instances."
  type        = bool
  default     = true
}

variable "irsa_oidc_issuer_url" {
  description = "Set to the cluster's OIDC issuer URL to give the agent its role through IRSA instead of EKS Pod Identity. The cluster's IAM OIDC provider must already exist."
  type        = string
  default     = null
}

variable "role_name" {
  description = "Name of the agent's role. Defaults to zoorik-agent-<cluster>, cut to 64 characters as zoorikctl does. A second cluster of the same name in this account takes zoorik-agent-<cluster>-<region>, the name zoorikctl uses then."
  type        = string
  default     = null
}
