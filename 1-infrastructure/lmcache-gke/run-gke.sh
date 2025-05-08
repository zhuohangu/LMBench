#!/bin/bash

set -x

# Check if number of GPUs argument is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <num_gpus>"
  exit 1
fi

NUM_GPUS=$1

CLUSTER_NAME="lm-bench"
NODE_POOL_NAME="gpu-pool"
ZONE="us-central1-a"
GCP_PROJECT=$(gcloud config get-value project)

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: No GCP project ID found. Please set your project with 'gcloud config set project <PROJECT_ID>'."
  exit 1
fi

# Choose machine type and accelerator
if [ "$NUM_GPUS" -eq 1 ]; then
  MACHINE_TYPE="a2-highgpu-1g" # 12 vCPUs, 85GB memory
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 2 ]; then
  MACHINE_TYPE="a2-highgpu-2g" # 24 vCPUs, 170GB memory
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 4 ]; then
  MACHINE_TYPE="a2-highgpu-4g" # 48 vCPUs, 340GB memory
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 8 ]; then
  MACHINE_TYPE="a2-highgpu-8g" # 96 vCPUs, 680GB memory
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 16 ]; then
  MACHINE_TYPE="a2-ultragpu-16g" # 128 vCPUs, 1920GB memory
  ACCELERATOR_TYPE="nvidia-a100-80gb"
else
  echo "Error: Only 1, 2, 4, 8 (A100 40GB) or 16 (A100 80GB) GPUs are supported."
  exit 1
fi

# Create cluster with no nodes
gcloud beta container --project "$GCP_PROJECT" clusters create "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --tier "standard" \
  --no-enable-basic-auth \
  --cluster-version "1.32.3-gke.1927000" \
  --release-channel "regular" \
  --image-type "COS_CONTAINERD" \
  --disk-type "pd-balanced" \
  --disk-size "100" \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append" \
  --machine-type "e2-medium" \
  --num-nodes "1" \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,CADVISOR,KUBELET \
  --enable-ip-alias \
  --network "projects/$GCP_PROJECT/global/networks/default" \
  --subnetwork "projects/$GCP_PROJECT/regions/us-central1/subnetworks/default" \
  --no-enable-intra-node-visibility \
  --default-max-pods-per-node "110" \
  --enable-ip-access \
  --security-posture=standard \
  --workload-vulnerability-scanning=disabled \
  --no-enable-master-authorized-networks \
  --no-enable-google-cloud-access \
  --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --binauthz-evaluation-mode=DISABLED \
  --enable-managed-prometheus \
  --enable-shielded-nodes \
  --node-locations "$ZONE"


# Create GPU node pool (for the serving engines)
gcloud container node-pools create gpu-pool \
  --cluster "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --accelerator type="$ACCELERATOR_TYPE",count="$NUM_GPUS" \
  --num-nodes "1" \
  --image-type=COS_CONTAINERD \
  --enable-autoupgrade \
  --enable-autorepair

# CPU only node pool (for the router)
gcloud container node-pools create cpu-pool \
  --cluster "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --machine-type "e2-standard-4" \
  --num-nodes "1"

echo "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"

echo "Labeling nodes in gpu and cpu pools..."
# Label GPU nodes
for node in $(kubectl get nodes -o name | grep gpu-pool); do
    kubectl label "$node" pool=gpu-pool
done

# Label CPU nodes
for node in $(kubectl get nodes -o name | grep cpu-pool); do
    kubectl label "$node" pool=cpu-pool
done

echo "Patching router and model serving deployments..."
# Patch router
kubectl patch deployment vllm-deployment-router \
  -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "cpu-pool"}}}}}'

# Patch all model serving deployments
for deploy in $(kubectl get deployments -o name | grep deployment-vllm); do
  kubectl patch "$deploy" \
    -p '{"spec": {"template": {"spec": {"nodeSelector": {"pool": "gpu-pool"}}}}}'
done
echo "Assigned router and model serving deployments to cpu and gpu pools respectively"

# Apply NVIDIA device plugin
PLUGIN_YAML_LOCAL="1-infrastructure/lmcache-gke/nvidia-device-plugin.yml"
PLUGIN_YAML_REMOTE="https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.4/nvidia-device-plugin.yml"

if [ -f "$PLUGIN_YAML_LOCAL" ]; then
    echo "✅ Using local NVIDIA device plugin YAML at $PLUGIN_YAML_LOCAL"
    kubectl apply -f "$PLUGIN_YAML_LOCAL"
else
    echo "🌐 Local file not found — using remote NVIDIA device plugin YAML from GitHub"
    kubectl apply -f "$PLUGIN_YAML_REMOTE"
fi