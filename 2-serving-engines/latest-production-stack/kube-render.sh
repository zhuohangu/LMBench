#! /bin/bash


# take three arguments:
# useLMCache
# modelURL
# hf_token
# enablePrefixCaching

# steps:

# 0. go into the current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 1. git clone latest production stack
git clone https://github.com/vllm-project/production-stack.git

# 2. go to /helm folder

# 3. use substitution on values.yaml
# make sure the vllm api key remains commented out (or else the open ai client has to know the key)
# start uncommenting from modelSpec
# remove the line      "runtimeClassName: nvidia" (or any line containing "runtimeClassName")
# substitute lmcacheConfig.enabled: {true, false}
# comment out modelSpec: []
    # TODO: later support multiple models
# remove line      enableChunkedPrefill: false (or any line containing "enableChunkedPrefill")
# substitute modelURL, name, and model entries (key names) with the given modelURL from bench-spec.yaml
# change "LMCacheConnector" to "LMCacheConnectorV1"
# increase the PVC size to 180Gi

# 4. run:
# a. if lmcache is disabled:
# helm template latest-vllm . -f values.yaml > latest-vllm.yaml

# b. if lmcache is enabled:
# helm template latest-lmcache . -f values.yaml > latest-lmcache.yaml

# 5. copy the rendered yaml (either latest-vllm.yaml or latest-lmcache.yaml) to the latest-results folder

# 6. run kubectl apply on the rendered yaml (either latest-vllm.yaml or latest-lmcache.yaml)
# see kube-deploy.sh for reference on how to apply a file (make sure to apply the rendered and not the values)
# make sure the:
# "kubectl port-forward <NAME>-router-service 30080:80 &"
# uses <NAME> as the name of the release (from the helm templating)
# this should be (if all instructions above are followed verbatim)
    # svc/latest-vllm-router-service if using vllm
    # svc/latest-lmcache-router-service if using lmcache
