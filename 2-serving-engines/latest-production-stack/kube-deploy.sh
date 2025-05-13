#! /bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

use_lmcache=$1

# true or True or TRUE
if [ "$use_lmcache" == "true" ] || [ "$use_lmcache" == "True" ] || [ "$use_lmcache" == "TRUE" ]; then
    echo "Using LMCache"
    kubectl apply -f lmcache.yaml
else
    echo "Using vLLM"
    kubectl apply -f vllm.yaml
fi

# Wait until all vllm pods are ready
echo "Waiting for all vLLM pods to be ready..."
while true; do
  PODS=$(kubectl get pods 2>/dev/null)

  TOTAL=$(echo "$PODS" | tail -n +2 | wc -l)
  READY=$(echo "$PODS" | grep '1/1' | wc -l)

  kubectl get pods -o name | grep deployment-vllm | while read pod; do
    echo "Checking logs for $pod for CUDA OOM"
    if kubectl logs $pod --tail=50 | grep "CUDA out of memory" >/dev/null; then
      echo "❗ CUDA OOM detected in $pod"
      exit 1
    fi
  done

  # TODO: uncomment once Helm is deubugged!
  Check for CrashLoopBackOff or other bad states
  if echo "$PODS" | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' > /dev/null; then
    echo "❌ Detected pod in CrashLoopBackOff / Error / ImagePullBackOff state!"
    kubectl get pods
    kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep '^vllm-' | xargs kubectl describe pod
    kubectl delete all --all
    exit 1
  fi

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

kubectl port-forward svc/latest-vllm-router-service 30080:80 &
# kubectl port-forward svc/latest-lmcache-router-service 30080:80 &