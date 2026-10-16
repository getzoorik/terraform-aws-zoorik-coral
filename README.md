# terraform-aws-zoorik-coral

The AWS permissions the Coral agent needs on one EKS cluster. It creates the same role, inline policy and Pod Identity association that `zoorikctl connect` creates. The trust and the policy are written exactly as zoorikctl writes them, so zoorikctl sees them as done and never rewrites them.

## What it creates

- The IAM role `zoorik-agent-<cluster>`, tagged `zoorik-cluster=<cluster ARN>`. Like zoorikctl, the module cuts the name to 64 characters. Only EKS Pod Identity may assume the role, and only for `zoorik-agent/zoorik-agent` on this cluster; the trust checks the session tags.
- The inline policy `ZoorikNodeRemoval-<cluster>-<hash>`, which allows:
  - describing Auto Scaling groups and instances;
  - simulating the role's own policy;
  - terminating instances in this cluster's groups, meaning those tagged `kubernetes.io/cluster/<cluster>=owned` or `eks:cluster-name=<cluster>`.
- With `lower_minimums`, the policy also lets the agent:
  - update only the minimum of those groups;
  - describe and update this cluster's managed node groups;
  - write only the tags `coral.zoorik.com/original-min` and `coral.zoorik.com/lowered-min`.
- The EKS Pod Identity association for `zoorik-agent/zoorik-agent`.

When `irsa_oidc_issuer_url` is set, the role trusts the cluster's IAM OIDC provider for that service account instead, and the module creates no association.

## Before you apply

- For Pod Identity, install the `eks-pod-identity-agent` add-on, unless EKS Auto Mode is on.
- For Pod Identity, apply this module before installing the coral-agent chart: the agent gets AWS credentials only if the association exists when its pod starts. If the agent already runs, restart it once after the apply: `kubectl --context <context> -n zoorik-agent rollout restart deployment/zoorik-agent`.
- For IRSA, the cluster's IAM OIDC provider must already exist.
- Point the aws provider at the cluster's account and region.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | | The EKS cluster's name. |
| `lower_minimums` | bool | `true` | Lets the agent lower a group's or node group's minimum size. |
| `irsa_oidc_issuer_url` | string | `null` | The cluster's OIDC issuer URL. Set it to use IRSA instead of EKS Pod Identity. |
| `role_name` | string | `null` | Overrides the role name. A second cluster with the same name in this account uses `zoorik-agent-<cluster>-<region>`, which is the name zoorikctl picks in that case. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | The ARN of the agent's role. |

## Helm values for the coral-agent chart

With EKS Pod Identity:

```yaml
clusterResourceId: <cluster ARN>
```

With IRSA:

```yaml
clusterResourceId: <cluster ARN>
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <role_arn>
```

The namespace and the service account are both fixed at `zoorik-agent`, because the trust and the association are bound to them.

## Your own node group code

The agent changes some values that your Terraform may also manage:

- It lowers a group's minimum size and records the old value in the tags `coral.zoorik.com/original-min` and `coral.zoorik.com/lowered-min`.
- Each node it removes also lowers the group's desired size.

Disconnect puts the minimum back. If Terraform manages those groups, ignore these changes, or each apply undoes them:

```hcl
lifecycle {
  ignore_changes = [
    scaling_config[0].min_size,
    scaling_config[0].desired_size,
    tags["coral.zoorik.com/original-min"],
    tags["coral.zoorik.com/lowered-min"],
  ]
}
```

That block is for `aws_eks_node_group`. For `aws_autoscaling_group`, ignore `min_size`, `desired_capacity` and `tag`.
