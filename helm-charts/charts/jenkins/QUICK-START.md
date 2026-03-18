# Quick Start Guide - Jenkins on EKS with EFS

## Your EFS Configuration
- **File System ID**: `fs-0f0d06710be37f34b`
- **Access Point ID**: `fsap-0cd91c042b87f9cf0`

## Quick Installation Steps

```bash
# 1. Install EFS CSI Driver
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver -n kube-system

# 2. Create namespace and install Jenkins
kubectl create namespace jenkins
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values values-eks-nondomain.yaml \
  --timeout 10m

# 3. Get LoadBalancer URL
kubectl get svc jenkins -n jenkins

# 4. Get admin password
kubectl exec -n jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
```

## What Gets Created Automatically

The `values-eks-nondomain.yaml` file configures:
- ✅ EFS StorageClass (efs-sc)
- ✅ PersistentVolume with your Access Point
- ✅ PersistentVolumeClaim
- ✅ Jenkins StatefulSet
- ✅ LoadBalancer Service (no domain needed)

## Access Jenkins

After installation completes:
1. Get the LoadBalancer URL: `kubectl get svc jenkins -n jenkins`
2. Open: `http://<LOAD_BALANCER_URL>:8080`
3. Login: `admin` / `Admin@123456`

## Important: Change Default Password

Edit `values-eks-nondomain.yaml` before installation:
```yaml
controller:
  admin:
    username: "admin"
    password: "YOUR_SECURE_PASSWORD_HERE"  # Change this!
```

## Verify Installation

```bash
# Check all resources
kubectl get all -n jenkins
kubectl get pvc -n jenkins
kubectl get pv

# Check EFS mount
kubectl exec -n jenkins -it jenkins-0 -- df -h | grep jenkins_home
```

## Troubleshooting

```bash
# Pod not starting?
kubectl describe pod jenkins-0 -n jenkins
kubectl logs jenkins-0 -n jenkins -c jenkins

# PVC not bound?
kubectl describe pvc jenkins -n jenkins

# EFS CSI issues?
kubectl get pods -n kube-system | grep efs
kubectl logs -n kube-system -l app=efs-csi-controller
```

## Full Documentation

See `DEPLOYMENT-GUIDE-EKS-EFS.md` for complete setup including:
- IAM roles and policies
- Security group configuration
- Detailed troubleshooting
- Production considerations
