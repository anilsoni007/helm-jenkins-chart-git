# Jenkins on EKS with EFS Deployment Guide

## Prerequisites

- EKS cluster running
- kubectl configured to access your EKS cluster
- Helm 3 installed
- EFS File System created: `fs-0f0d0671xxxxx`
- EFS Access Point created: `fsap-0cd91c042bxxxxxxx`

## Step 1: Install EFS CSI Driver

```bash
# Add the AWS EFS CSI Driver Helm repository
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Install the EFS CSI Driver
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=efs-csi-controller-sa
```

**Note:** Replace `us-east-1` with your AWS region in the image repository URL.

## Step 2: Configure IAM for EFS CSI Driver (IRSA)

```bash
# Get your cluster name and region
CLUSTER_NAME="your-cluster-name"
REGION="us-east-1"

# Create IAM policy for EFS
cat > efs-csi-driver-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:CreateAccessPoint",
        "elasticfilesystem:DeleteAccessPoint",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create the IAM policy
aws iam create-policy \
  --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
  --policy-document file://efs-csi-driver-policy.json

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=efs-csi-controller-sa \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --approve \
  --region=$REGION
```

## Step 3: Verify EFS Security Group

Ensure your EFS security group allows NFS traffic (port 2049) from your EKS worker nodes:

```bash
# Get your EKS cluster security group
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId"

# Add inbound rule to EFS security group
EFS_SG_ID="sg-xxxxx"  # Your EFS security group ID
CLUSTER_SG_ID="sg-yyyyy"  # Your cluster security group ID

aws ec2 authorize-security-group-ingress \
  --group-id $EFS_SG_ID \
  --protocol tcp \
  --port 2049 \
  --source-group $CLUSTER_SG_ID
```

## Step 4: Install Jenkins with EFS

The Helm chart has built-in EFS support. Simply install with the custom values file:

```bash
# Create namespace for Jenkins
kubectl create namespace jenkins

# Add Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io
helm repo update

# Install Jenkins with EFS configuration
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values values-eks-nondomain.yaml \
  --timeout 10m

# Or upgrade if already installed
helm upgrade jenkins jenkins/jenkins \
  --namespace jenkins \
  --values values-eks-nondomain.yaml \
  --timeout 10m
```

The Helm chart will automatically create:
- EFS StorageClass
- PersistentVolume with your EFS Access Point
- PersistentVolumeClaim

## Step 5: Verify Installation

```bash
# Check if resources are created
kubectl get sc
kubectl get pv
kubectl get pvc -n jenkins
kubectl get pods -n jenkins

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=jenkins-controller -n jenkins --timeout=600s
```

## Step 6: Get Jenkins URL and Admin Password

```bash
# Wait for LoadBalancer to be provisioned
kubectl get svc -n jenkins -w

# Get the LoadBalancer URL
export JENKINS_URL=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Jenkins URL: http://$JENKINS_URL:8080"

# Get admin password (if not set in values file)
kubectl exec -n jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
```

## Step 7: Access Jenkins

1. Open browser and navigate to: `http://<LOAD_BALANCER_URL>:8080`
2. Login with:
   - Username: `admin`
   - Password: `Admin@123456` (or the password you set in values file)

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n jenkins
kubectl describe pod jenkins-0 -n jenkins
kubectl logs jenkins-0 -n jenkins -c jenkins
```

### Check PVC Status
```bash
kubectl get pvc -n jenkins
kubectl describe pvc jenkins -n jenkins
```

### Check EFS Mount
```bash
kubectl exec -n jenkins -it jenkins-0 -- df -h | grep jenkins_home
```

### Verify EFS CSI Driver
```bash
kubectl get pods -n kube-system | grep efs
kubectl logs -n kube-system -l app=efs-csi-controller
```

### Check StorageClass and PV
```bash
kubectl get sc
kubectl get pv
kubectl describe pv jenkins-efs-pv
```

## Uninstall

```bash
# Uninstall Jenkins
helm uninstall jenkins -n jenkins

# Delete PVC (optional - this will delete your data)
kubectl delete pvc jenkins -n jenkins

# Delete namespace (optional)
kubectl delete namespace jenkins
```

## Important Notes

1. **Security**: Change the default admin password in `values-eks-nondomain.yaml` before deployment
2. **Backup**: EFS data persists even after uninstalling Jenkins. Consider implementing backup strategy
3. **Cost**: Network Load Balancer incurs AWS charges
4. **Access**: The LoadBalancer is publicly accessible. Consider using security groups to restrict access
5. **SSL**: For production, configure SSL/TLS termination at the load balancer level
6. **Monitoring**: Enable CloudWatch monitoring for EFS and EKS

## Next Steps

1. Configure Jenkins pipelines
2. Set up GitHub/GitLab webhooks
3. Configure additional plugins
4. Set up backup strategy for EFS
5. Configure SSL certificate for LoadBalancer
6. Set up monitoring and alerting
