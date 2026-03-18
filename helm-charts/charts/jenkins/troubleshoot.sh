#!/bin/bash
# Troubleshooting script for Jenkins init container failure

echo "=== Checking init container logs ==="
kubectl logs jenkins-0 -n jenkins -c init

echo ""
echo "=== Checking init container previous logs ==="
kubectl logs jenkins-0 -n jenkins -c init --previous

echo ""
echo "=== Checking EFS CSI driver ==="
kubectl get pods -n kube-system | grep efs

echo ""
echo "=== Checking StorageClass ==="
kubectl get sc efs-sc -o yaml

echo ""
echo "=== Checking PV ==="
kubectl get pv jenkins-efs-pv -o yaml

echo ""
echo "=== Checking PVC ==="
kubectl get pvc jenkins -n jenkins -o yaml

echo ""
echo "=== Checking if EFS is mounted ==="
kubectl exec jenkins-0 -n jenkins -c config-reload-init -- df -h 2>/dev/null || echo "Container not ready"
