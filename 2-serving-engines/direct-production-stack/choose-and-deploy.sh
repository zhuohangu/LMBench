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

# PATCHING DEPLOYMENTS TO USE APPROPRIATE NODE POOLS
echo "Assigning deployments to node pools based on type..."

# Give kubernetes a moment to create the resources
sleep 5

# Check for router deployment - using consistent name from k8s config files
echo "Patching router deployment to use CPU nodes..."
if kubectl get deployment vllm-deployment-router &>/dev/null; then
    kubectl patch deployment vllm-deployment-router \
        -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "cpu-pool"}}}}}'
    echo "✅ vllm-deployment-router assigned to cpu-pool"
else
    echo "⚠️ Router deployment not found to patch"
fi

# Check for model serving deployments - using pattern from k8s config files
echo "Patching model deployments to use GPU nodes..."
DEPLOYMENTS=$(kubectl get deployments -o name 2>/dev/null)
if [ $? -eq 0 ]; then
    # Find vllm model deployments with the naming pattern used in the configs
    VLLM_DEPLOYMENTS=$(echo "$DEPLOYMENTS" | grep 'deployment.*/vllm-.*deployment-vllm')

    if [ -n "$VLLM_DEPLOYMENTS" ]; then
        echo "$VLLM_DEPLOYMENTS" | while read deploy; do
            kubectl patch $deploy \
                -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "gpu-pool"}}}}}'
            echo "✅ $(echo $deploy | sed 's|deployment.apps/||') assigned to gpu-pool"
        done
    else
        echo "⚠️ No model serving deployments found matching pattern"
        # Try a broader pattern as fallback
        VLLM_DEPLOYMENTS=$(echo "$DEPLOYMENTS" | grep -v 'router')
        if [ -n "$VLLM_DEPLOYMENTS" ]; then
            echo "Trying with broader pattern..."
            echo "$VLLM_DEPLOYMENTS" | while read deploy; do
                if [[ $deploy != *"router"* ]]; then
                    kubectl patch $deploy \
                        -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "gpu-pool"}}}}}'
                    echo "✅ $(echo $deploy | sed 's|deployment.apps/||') assigned to gpu-pool"
                fi
            done
        fi
    fi
else
    echo "⚠️ Error getting deployments list"
fi

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

