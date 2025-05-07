#!/usr/bin/env python3

import yaml
import os
import subprocess
from pathlib import Path
from typing import Dict, Any, Union, Optional
import sys

GLOBAL_ARGS = None # MIGHT be set in parse_args()

# Global variables passed between stages in the pipeline
MODEL_URL = None # MUST be set in setup_baseline()
HF_TOKEN = None # MUST be set in setup_baseline()
KEY = None # MUST be set in run_workload()

def read_bench_spec() -> Dict[str, Any]:
    """Read and parse the bench-spec.yaml file."""
    with open('bench-spec.yaml', 'r') as f:
        return yaml.safe_load(f)

# 1. Infrastructure Setup
def setup_infrastructure(config: Dict[str, Any]) -> None:
    """Set up the infrastructure based on the configuration."""
    if 'Infrastructure' not in config:
        raise ValueError("Infrastructure configuration is missing in bench-spec.yaml")

    location = config['Infrastructure'].get('Location')
    if not location:
        raise ValueError("Infrastructure Location is not specified in bench-spec.yaml")

    if location == 'Minikube':
        minikube_installation(config)
    elif location == 'LMCacheGKE':
        start_gke_cluster(config)
    else:
        raise ValueError(f"Unsupported infrastructure location: {location}")

def minikube_installation(config: Dict[str, Any]) -> None:
    script_path = Path(__file__).parent / '1-infrastructure' / 'local-minikube' / 'install-local-minikube.sh'

    if not script_path.exists():
        raise FileNotFoundError(f"Installation script not found at {script_path}")

    # Make the script executable if it isn't already
    os.chmod(script_path, 0o755)

    # Execute the installation script
    print("Setting up local minikube environment...")
    # This is blocking
    result = subprocess.run([str(script_path)], check=True)

    if result.returncode == 0:
        print("Local minikube environment setup completed successfully")
    else:
        raise RuntimeError("Failed to set up local minikube environment")

def start_gke_cluster(config: Dict[str, Any]) -> None:
    script_path = Path(__file__).parent / '1-infrastructure' / 'lmcache-gke' / 'run-gke.sh'
    if not script_path.exists():
        raise FileNotFoundError(f"GKE cluster setup script not found at {script_path}")

    # add execution permission
    os.chmod(script_path, 0o755)

    # Execute the script
    num_gpus = config['Infrastructure'].get('numClusterGPUs')
    if not num_gpus:
        raise ValueError("numClusterGPUs must be specified in bench-spec.yaml for GKE cluster setup")
    result = subprocess.run([str(script_path), str(num_gpus)], check=True)

    if result.returncode == 0:
        print("GKE cluster setup completed successfully")
    else:
        raise RuntimeError("Failed to set up GKE cluster")

# 2. Baseline Setup
def setup_baseline(config: Dict[str, Any]) -> None:
    """Set up the baseline (cluster of serving engines) based on the configuration."""
    if 'Serving' not in config:
        raise ValueError("Serving configuration is missing in bench-spec.yaml")

    baseline = config['Serving'].get('Baseline')
    global MODEL_URL # saved for later steps
    global HF_TOKEN # saved for later steps
    global KEY # saved for later steps
    if baseline == 'SGLang':
        KEY = 'sglang'
        single_config = config['Serving'].get('SGLang', {})
        model_url = single_config.get('modelURL')
        hf_token = single_config.get('hf_token')
        if not model_url:
            raise ValueError("modelURL must be specified in bench-spec.yaml for SGLang baseline")
        if not hf_token:
            raise ValueError("hf_token must be specified in bench-spec.yaml for SGLang baseline")
        MODEL_URL = model_url
        HF_TOKEN = hf_token

        # TODO
        pass
    elif baseline == 'ProductionStack':
        KEY = 'stack'
        prodstack_config = config['Serving'].get('ProductionStack', {})
        model_url = prodstack_config.get('modelURL')
        hf_token = prodstack_config.get('hf_token')
        if not model_url:
            raise ValueError("modelURL must be specified in bench-spec.yaml for ProductionStack baseline")
        if not hf_token:
            raise ValueError("hf_token must be specified in bench-spec.yaml for ProductionStack baseline")
        MODEL_URL = model_url
        HF_TOKEN = hf_token

        # helm installation
        helm_installation(prodstack_config)
    elif baseline == 'Dynamo':
        KEY = 'dynamo'
        #TODO
        dynamo_config = config['Serving'].get('Dynamo', {})
        pass
    else:
        raise ValueError(f"Unsupported baseline: {baseline}")

def helm_installation(prodstack_config: Dict[str, Any]) -> None:
    """
    Deploy the router and serving engines through production stack helm installation
    """
    prodstack_base_name = 'v0-base-production-stack.yaml'
    generated_name = 'v0-generated-production-stack.yaml'
    if prodstack_config.get('vLLM-Version') == 1:
        prodstack_base_name = 'v1-base-production-stack.yaml'
        generated_name = 'v1-generated-production-stack.yaml'

    base_yaml_file = Path(__file__).parent / '2-serving-engines' / 'production-stack' / prodstack_base_name

    if not base_yaml_file.exists():
        raise FileNotFoundError(f"Base YAML file not found: {base_yaml_file}")

    with open(base_yaml_file, 'r') as f:
        base_config = yaml.safe_load(f)

    updated_config = _override_yaml(base_config, prodstack_config)

    # dump the updated config to the latest results folder for visibility
    output_path = Path(__file__).parent / "4-latest-results" / generated_name
    with open(output_path, 'w') as out:
        yaml.dump(updated_config, out, default_flow_style=False)
        print(f"Generated config written to {output_path}")

    # Run the helm installation script
    install_script = Path(__file__).parent / '2-serving-engines' / 'production-stack' / 'helm-install.sh'
    os.chmod(install_script, 0o755)
    print("Running Helm install script...")
    subprocess.run([str(install_script), str(output_path)], check=True)

def _override_yaml(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    try:
        model_spec = base['servingEngineSpec']['modelSpec'][0]
        vllm_config = model_spec['vllmConfig']
        lmcache_config = model_spec.get('lmcacheConfig', {})
    except (KeyError, IndexError, TypeError):
        raise ValueError("Expected structure missing in base YAML")

    # Apply only known, nested overrides
    mapping = {
        'modelURL': lambda v: model_spec.update({'modelURL': v}),
        'replicaCount': lambda v: model_spec.update({'replicaCount': v}),
        'hf_token': lambda v: model_spec.update({'hf_token': v}),
        'numGPUs': lambda v: model_spec.update({'requestGPU': v}),
        'numCPUs': lambda v: model_spec.update({'requestCPU': v}),
        'maxModelLen': lambda v: vllm_config.update({'maxModelLen': v}),
        'tensorParallelSize': lambda v: vllm_config.update({'tensorParallelSize': v}),
        'useLMCache': lambda v: lmcache_config.update({'enabled': bool(v)}),
        'cpuSize': lambda v: lmcache_config.update({'cpuOffloadingBufferSize': str(v)}),
    }

    for key, val in override.items():
        handler = mapping.get(key)
        if handler:
            handler(val)
        else:
            print(f"[warn] Ignoring unrecognized override key: '{key}'")

    return base

# 3. Run the specified workload
def run_workload(config: Dict[str, Any]) -> None:
    """Run the specified workload based on the configuration."""
    if 'Workload' not in config:
        raise ValueError("Workload configuration is missing in bench-spec.yaml")

    global MODEL_URL
    if not MODEL_URL:
        raise ValueError("MODEL_URL is not set when trying to run the workload. It should have been set up regardless of what baseline was used!")

    global HF_TOKEN
    if not HF_TOKEN:
        raise ValueError("HF_TOKEN is not set when trying to run the workload. It should have been set up regardless of what baseline was used!")

    global KEY
    if not KEY:
        raise ValueError("KEY is not set when trying to run the workload. It should have been set up regardless of what baseline was used!")

    # export HF_TOKEN
    os.environ['HF_TOKEN'] = HF_TOKEN

    workload_cfg = config['Workload']

    supported_workloads = ['ShareGPT', 'LMCacheSynthetic', 'Agentic', 'Mooncake']
    for workload in workload_cfg:
        if workload not in supported_workloads:
            raise ValueError(f"Unsupported workload type: {workload}")

    # Multiple workloads can be run
    if 'ShareGPT' in workload_cfg:
        sharegpt_config = workload_cfg['ShareGPT']
        run_sharegpt(sharegpt_config)

    if 'LMCacheSynthetic' in workload_cfg:
        #TODO
        pass

    if 'Agentic' in workload_cfg:
        #TODO
        pass

    if 'Mooncake' in workload_cfg:
        #TODO
        pass

def run_sharegpt(sharegpt_config: Dict[str, Any]) -> None:
    """Run the ShareGPT workload with the specified configuration."""
    if not GLOBAL_ARGS.ignore_data_generation:
        sharegpt_data_generation(sharegpt_config)
    sharegpt_run_workload(sharegpt_config)

def sharegpt_data_generation(sharegpt_config: Dict[str, Any]) -> None:
    # Get ShareGPT specific parameters with defaults
    limit = sharegpt_config.get('LIMIT')
    min_rounds = sharegpt_config.get('MIN_ROUNDS')
    start_round = sharegpt_config.get('START_ROUND')

    # Construct the command with parameters
    data_gen_script_path = Path(__file__).parent / '3-workloads' / 'sharegpt' / 'data_generation' / 'prepare_sharegpt_data.sh'

    if not data_gen_script_path.exists():
        raise FileNotFoundError(f"ShareGPT script not found at {data_gen_script_path}")

    # Make the script executable
    os.chmod(data_gen_script_path, 0o755)

    global MODEL_URL
    cmd = [str(data_gen_script_path)]
    if limit is not None:
        cmd.extend(['-l', str(limit)])
    if min_rounds is not None:
        cmd.extend(['-m', str(min_rounds)])
    if start_round is not None:
        cmd.extend(['-s', str(start_round)])
    cmd.extend(['--model-url', str(MODEL_URL)])

    # Execute data generation script
    print(f"Generating and processing ShareGPT data with parameters: {' '.join(cmd)}")
    result = subprocess.run(cmd, check=True)

    if result.returncode == 0:
        print("ShareGPT data generation completed successfully into 4-latest-results/sharegpt-data.json")
    else:
        raise RuntimeError("Failed to generate ShareGPT data")

def sharegpt_run_workload(sharegpt_config: Dict[str, Any]) -> None:
    # should be a list
    qps_values = sharegpt_config.get('QPS')
    workload_exec_script_path = Path(__file__).parent / '3-workloads' / 'sharegpt' / 'workload_execution' / 'run-sharegpt.sh'

    if not workload_exec_script_path.exists():
        raise FileNotFoundError(f"ShareGPT script not found at {workload_exec_script_path}")

    os.chmod(workload_exec_script_path, 0o755)

    cmd = [str(workload_exec_script_path)]
    cmd.extend([str(MODEL_URL)])
    cmd.extend(["http://localhost:30080/v1/"]) # the base URL when serving with production stack
    cmd.extend([KEY]) # the key that will be embedded in the filenames of the results
    cmd.extend([str(qps) for qps in qps_values])

    # Execute the workload
    print(f"Running ShareGPT workload with parameters: {' '.join(cmd)}")
    result = subprocess.run(cmd, check=True)

    if result.returncode == 0:
        print("ShareGPT workload completed successfully into 4-latest-results/sharegpt-summary.csv")
    else:
        raise RuntimeError("Failed to run ShareGPT workload")

    # do post processing
    # run 4-latest-results/post-processing/summarize.py
    summarize_script_path = Path(__file__).parent / '4-latest-results' / 'post-processing' / 'summarize.py'
    os.chmod(summarize_script_path, 0o755)
    # find all .csv files in 4-latest-results/
    csv_files = Path(__file__).parent.joinpath("4-latest-results").rglob("*.csv")

    for csv_path in csv_files:
        print(f"Post-processing {csv_path}...")
        cmd = ['python3', str(summarize_script_path), str(csv_path)]
        result = subprocess.run(cmd, check=True)
        if result.returncode == 0:
            print(f"Post-processing completed for {csv_path}")
        else:
            raise RuntimeError(f"Failed to post-process {csv_path}")

    if result.returncode == 0:
        print("ShareGPT workload post-processing completed successfully")
    else:
        raise RuntimeError("Failed to run ShareGPT workload post-processing")

def clean_up() -> None:
    """
    Does not need to specified in the bench-spec.yaml configuration
    """

    # run 4-latest-results/post-processing/cleanup.sh
    cleanup_script_path = Path(__file__).parent / '4-latest-results' / 'post-processing' / 'cleanup.sh'
    os.chmod(cleanup_script_path, 0o755)
    subprocess.run([str(cleanup_script_path)], check=True)

import argparse

def parse_args():
    parser = argparse.ArgumentParser(description="Run benchmarking pipeline.")
    parser.add_argument("--start-from", type=int, choices=[1, 2, 3], default=1,
                        help="Start pipeline from stage 1, 2, or 3 (default: 1)")
    parser.add_argument("--model-url", type=str, help="Inject a model URL if starting from stage 3")
    parser.add_argument("--port-forward-url", type=str,
                        help="Inject a port-forward base URL if starting from stage 2 or 3")
    parser.add_argument("--hf-token", type=str, help="Inject a HF token if starting from stage 3")
    parser.add_argument("--key", type=str, help="Inject a key if starting from stage 3")
    parser.add_argument("--ignore-data-generation", action="store_true", help="Ignore data generation and use existing data in 4-latest-results/sharegpt-data.json")
    return parser.parse_args()


# High-Level Benchmarking Pipeline
def main() -> None:
    args = parse_args()
    global GLOBAL_ARGS
    GLOBAL_ARGS = args
    print(f"Starting from stage {args.start_from}")

    if args.start_from < 1 or args.start_from > 3:
        raise ValueError("Invalid start-from argument. Must be 1 (infrastructure), 2 (baseline), or 3 (workload).")
    if args.model_url:
        print(f"Injecting model URL: {args.model_url}")
        global MODEL_URL
        MODEL_URL = args.model_url
    if args.hf_token:
        print(f"Injecting HF token: {args.hf_token}")
        global HF_TOKEN
        HF_TOKEN = args.hf_token
    if args.port_forward_url:
        print(f"Injecting port-forward URL: {args.port_forward_url}")
        global PORT_FORWARD_URL
        PORT_FORWARD_URL = args.port_forward_url
    if args.key:
        print(f"Injecting key: {args.key}")
        global KEY
        KEY = args.key
    if args.ignore_data_generation:
        print("Ignoring data generation!")

    try:
        # Read the configuration
        config = read_bench_spec()

        # 1. Set up infrastructure
        if args.start_from <= 1:
            setup_infrastructure(config)

        # 2. Set up baseline (cluster of serving engines)
        if args.start_from <= 2:
            setup_baseline(config)

        # 3. Run the specified workload
        run_workload(config)

    except Exception as e:
        print(f"Benchmarking Error: {str(e)}")
        sys.exit(1)

    finally:
        clean_up()

if __name__ == "__main__":
    main()
