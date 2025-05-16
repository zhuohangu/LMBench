#!/bin/bash
set -e

# switch to 4-latest-results folder (parent is already in parent of 4-latest-results)
cd 4-latest-results/

echo "Current directory: $(pwd)"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <values-file.yaml>"
  exit 1
fi

VALUES_FILE="$1"

# Add Helm repo if not already added
helm repo add vllm https://vllm-project.github.io/production-stack || true

# Kill any process using port 30080
if lsof -ti :30080 > /dev/null; then
  echo "⚠️  Port 30080 is already in use. Killing existing process..."
  kill -9 $(lsof -ti :30080)
fi

# Make sure there is no current release
echo "Uninstalling any existing helm releases..."
helm uninstall vllm || true

# More thorough cleanup of any leftover deployments
echo "Cleaning up any lingering deployments..."
kubectl delete deployment -l helm-release-name=vllm --ignore-not-found=true
# Delete any stale pods directly as well
kubectl delete pods -l helm-release-name=vllm --ignore-not-found=true

# Wait for all resources to be fully deleted
echo "Waiting for all resources to be fully deleted..."
while true; do
  # Check for any remaining pods or deployments
  PODS=$(kubectl get pods -l helm-release-name=vllm 2>/dev/null | grep -v "No resources found" || true)
  DEPLOYMENTS=$(kubectl get deployments -l helm-release-name=vllm 2>/dev/null | grep -v "No resources found" || true)

  if [ -z "$PODS" ] && [ -z "$DEPLOYMENTS" ]; then
    echo "✅ All previous resources have been cleaned up"
    break
  fi

  echo "⏳ Waiting for resources to be deleted..."
  sleep 3
done

# Double check that we have no pods at all before proceeding
while true; do
  if [ $(kubectl get pods | wc -l) -eq 0 ]; then
    break
  fi
  sleep 1
done

# Install the stack
echo "Installing vLLM stack..."
# release name is vllm
helm install vllm vllm/vllm-stack -f "$VALUES_FILE"

# PATCHING DEPLOYMENTS TO USE APPROPRIATE NODE POOLS
echo "Assigning deployments to node pools based on type..."

# Give kubernetes a moment to create the resources
sleep 5

# Check for router deployment - try multiple possible names
echo "Patching router deployment to use CPU nodes..."
if kubectl get deployment vllm-router-deployment &>/dev/null; then
    kubectl patch deployment vllm-router-deployment \
        -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "cpu-pool"}}}}}'
    echo "✅ vllm-router-deployment assigned to cpu-pool"
elif kubectl get deployment vllm-router &>/dev/null; then
    kubectl patch deployment vllm-router \
        -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "cpu-pool"}}}}}'
    echo "✅ vllm-router assigned to cpu-pool"
else
    echo "⚠️ No router deployment found to patch"
fi

# Check for model serving deployments
echo "Patching model deployments to use GPU nodes..."
DEPLOYMENTS=$(kubectl get deployments -o name 2>/dev/null)
if [ $? -eq 0 ]; then
    # Find all deployments that might be vllm model deployments
    VLLM_DEPLOYMENTS=$(echo "$DEPLOYMENTS" | grep -E 'deployment.*vllm|vllm.*deployment' | grep -v 'router')

    if [ -n "$VLLM_DEPLOYMENTS" ]; then
        echo "$VLLM_DEPLOYMENTS" | while read deploy; do
            kubectl patch $deploy \
                -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "gpu-pool"}}}}}'
        done
        echo "✅ Model serving deployments assigned to gpu-pool"
    else
        echo "⚠️ No model serving deployments found"
    fi
else
    echo "⚠️ Error getting deployments list"
fi

# Also patch the deployment strategy to reduce max surge to 0 (create new pods only after old ones are terminated)
echo "Patching deployment strategy to avoid creating excess pods..."
VLLM_DEPLOYMENTS=$(kubectl get deployments -l helm-release-name=vllm -o name 2>/dev/null | grep -v 'router')
if [ -n "$VLLM_DEPLOYMENTS" ]; then
    echo "$VLLM_DEPLOYMENTS" | while read deploy; do
        kubectl patch $deploy \
            -p '{"spec": {"strategy": {"rollingUpdate": {"maxSurge": 0, "maxUnavailable": 1}}}}'
    done
    echo "✅ Patched deployment strategy to reduce max surge"
fi

# Wait until all vllm pods are ready
echo "Waiting for all vLLM pods to be ready..."
while true; do
  PODS=$(kubectl get pods 2>/dev/null)

  TOTAL=$(echo "$PODS" | tail -n +2 | wc -l)
  READY=$(echo "$PODS" | grep '1/1' | wc -l)

  # Comment when debugging kubernetes
  if echo "$PODS" | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' > /dev/null; then
    echo "❌ Detected pod in CrashLoopBackOff / Error / ImagePullBackOff state!"
    kubectl get pods
    kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep '^vllm-' | xargs kubectl describe pod
    kubectl delete all --all
    exit 1
  fi

  kubectl get pods -o name | grep deployment-vllm | while read pod; do
    echo "Checking logs for $pod for CUDA OOM"
    if kubectl logs $pod --tail=50 | grep "CUDA out of memory" >/dev/null; then
      echo "❗ CUDA OOM detected in $pod"
      kubectl get pods
      kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep '^vllm-' | xargs kubectl describe pod
      kubectl delete all --all
      exit 1
    fi
  done

  if [ "$READY" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    echo "✅ All $TOTAL pods are running and ready."
    kubectl get pods
    break
  else
    echo "⏳ $READY/$TOTAL pods ready..."
    kubectl get pods
    sleep 15
  fi
done

echo "Ready for port forwarding!"

kubectl port-forward svc/vllm-router-service 30080:80 &