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
helm uninstall vllm || true

while true; do
  if [ $(kubectl get pods | wc -l) -eq 0 ]; then
    break
  fi
  sleep 1
done

# Install the stack
helm install vllm vllm/vllm-stack -f "$VALUES_FILE"

# Wait until all vllm pods are ready
echo "Waiting for all vLLM pods to be ready..."
while true; do
  PODS=$(kubectl get pods 2>/dev/null)

  TOTAL=$(echo "$PODS" | tail -n +2 | wc -l)
  READY=$(echo "$PODS" | grep '1/1' | wc -l)

  # TODO: uncomment once Helm is deubugged!
  # Check for CrashLoopBackOff or other bad states
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