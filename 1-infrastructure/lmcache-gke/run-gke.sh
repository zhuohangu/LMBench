#!/bin/bash

# Check if number of GPUs argument is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <num_gpus>"
  exit 1
fi

NUM_GPUS=$1

CLUSTER_NAME="lm-bench"
# this is a zone that has nvidia-a100-80gb GPUs
ZONE="us-central1-a"
# Get the current GCP project ID
GCP_PROJECT=$(gcloud config get-value project)

# Ensure the project ID is retrieved correctly
if [ -z "$GCP_PROJECT" ]; then
  echo "Error: No GCP project ID found. Please set your project with 'gcloud config set project <PROJECT_ID>'."
  exit 1
fi

# Choose the correct machine type and accelerator type based on GPU count
if [ "$NUM_GPUS" -eq 1 ]; then
  MACHINE_TYPE="a2-highgpu-1g"
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 2 ]; then
  MACHINE_TYPE="a2-highgpu-2g"
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 4 ]; then
  MACHINE_TYPE="a2-highgpu-4g"
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 8 ]; then
  MACHINE_TYPE="a2-highgpu-8g"
  ACCELERATOR_TYPE="nvidia-tesla-a100"
elif [ "$NUM_GPUS" -eq 16 ]; then
  MACHINE_TYPE="a2-ultragpu-16g"
  ACCELERATOR_TYPE="nvidia-a100-80gb"
else
  echo "Error: Only 1, 2, 4, 8 (A100 40GB) or 16 (A100 80GB) GPUs are supported."
  exit 1
fi

# Create the GKE cluster
gcloud beta container --project "$GCP_PROJECT" clusters create "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --tier "standard" \
  --no-enable-basic-auth \
  --cluster-version "1.32.3-gke.1927000" \
  --release-channel "regular" \
  --machine-type "$MACHINE_TYPE" \
  --accelerator type="$ACCELERATOR_TYPE",count="$NUM_GPUS" \
  --image-type "COS_CONTAINERD" \
  --disk-type "pd-balanced" \
  --disk-size "100" \
  --metadata disable-legacy-endpoints=true \
  --scopes \
    "https://www.googleapis.com/auth/devstorage.read_only,\
https://www.googleapis.com/auth/logging.write,\
https://www.googleapis.com/auth/monitoring,\
https://www.googleapis.com/auth/servicecontrol,\
https://www.googleapis.com/auth/service.management.readonly,\
https://www.googleapis.com/auth/trace.append" \
  --max-pods-per-node "110" \
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
