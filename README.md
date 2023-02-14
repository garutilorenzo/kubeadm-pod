# kubeadm-pod

Crontab like pod to update kubernetes join certificates. Supported providers **AWS** and **OCI**

## How it works

The pod runs on one of the master nodes of the cluster and the job will [create new certificates](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/#steps-for-the-rest-of-the-control-plane-nodes) needed to join the cluster.
This new certificates then are stored in **OCI -> Vault** for OCI provider and **AWS -> Secrets Manager** for AWS provider.

