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
# make sure the api key remains commented out
# start uncommenting from modelSpec
# remove line      runtimeClassName: nvidia (or any line containing "runtimeClassName")
# substitute lmcacheConfig.enabled {true, false}
# comment out modelSpec: []
# remove line      enableChunkedPrefill: false (or any line containing "enableChunkedPrefill")
# substitute modelURL, name, and model entries (key names) with the given modelURL

# 4. run:
# a. if lmcache is disabled:
# helm template latest-vllm . -f values.yaml > latest-vllm.yaml

# b. if lmcache is enabled:
# helm template latest-lmcache . -f values.yaml > latest-lmcache.yaml

# 5. copy the rendered yaml file to the latest-results folder

# 6. run kubectl apply on the rendered yaml file
# see kube-deploy.sh for reference
# make sure the:
# "kubectl port-forward <NAME>-router-service 30080:80 &"
# uses <NAME> as the name of the release (from the helm templating)
# use svc/latest-vllm-router-service if using vllm, or svc/latest-lmcache-router-service if using lmcache
