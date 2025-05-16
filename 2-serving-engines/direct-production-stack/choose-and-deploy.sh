#! /bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# This script will choose the correct kubernetes config file and apply it to the cluster

# Get the kubernetes config file name from the first argument
KUBE_CONFIG_FILENAME=$1

if [ -z "$KUBE_CONFIG_FILENAME" ]; then
    echo "Error: Kubernetes configuration filename not provided."
    echo "Usage: $0 <kubernetes_config_filename>"
    exit 1
fi

# Set the path to the kubernetes configurations directory
KUBE_CONFIG_DIR="$SCRIPT_DIR/kubernetes_configurations"
KUBE_CONFIG_FILE="$KUBE_CONFIG_DIR/$KUBE_CONFIG_FILENAME"

# Check if the file exists
if [ ! -f "$KUBE_CONFIG_FILE" ]; then
    echo "Error: Kubernetes configuration file not found: $KUBE_CONFIG_FILE"
    echo "Available configurations:"
    ls -la "$KUBE_CONFIG_DIR" || echo "No configurations directory found at $KUBE_CONFIG_DIR"
    exit 1
fi

echo "Applying Kubernetes configuration: $KUBE_CONFIG_FILE"
kubectl apply -f "$KUBE_CONFIG_FILE"

# Wait until all pods are ready
echo "Waiting for all pods to be ready..."
while true; do
  PODS=$(kubectl get pods 2>/dev/null)

  TOTAL=$(echo "$PODS" | tail -n +2 | wc -l)
  READY=$(echo "$PODS" | grep '1/1' | wc -l)

  # Check for pods in error state
  if echo "$PODS" | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' > /dev/null; then
    echo "❌ Detected pod in CrashLoopBackOff / Error / ImagePullBackOff state!"
    kubectl get pods
    kubectl describe pods | grep -A 10 "Events:"
    kubectl delete all --all
    exit 1
  fi

  # Check for CUDA OOM
  kubectl get pods -o name | grep -E 'vllm|lmcache' | while read pod; do
    echo "Checking logs for $pod for CUDA OOM"
    if kubectl logs $pod --tail=50 2>/dev/null | grep "CUDA out of memory" >/dev/null; then
      echo "❗ CUDA OOM detected in $pod"
      kubectl get pods
      kubectl describe pod $pod
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
    sleep 5
  fi
done

echo "Ready for port forwarding!"

# Start port forwarding in the background
kubectl port-forward svc/vllm-router-service 30080:80 &
echo "Port forwarding started on 30080"

