import pandas as pd
import sys
from typing import Optional
import os
import io
import contextlib
from datetime import datetime
import numpy as np
import yaml

def ProcessSummary(
    df: pd.DataFrame,
    start_time: Optional[float] = None,
    end_time: Optional[float] = None,
    pending_queries: int = 0,
    qps: Optional[float] = None,
) -> str:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        if start_time is not None and end_time is not None:
            launched_queries = len(df.query(f"{start_time} <= launch_time <= {end_time}"))
            df = df.query(f"{start_time} <= finish_time <= {end_time}")
        else:
            launched_queries = len(df)

        if qps is None:
            qps = 0.0

        if start_time is None:
            start_time = df["launch_time"].min()
        if end_time is None:
            end_time = df["finish_time"].max()

        total_time = end_time - start_time
        total_requests = launched_queries + pending_queries
        finished_requests = len(df)
        request_throughput = finished_requests / total_time

        total_prompt_tokens = df["prompt_tokens"].sum()
        total_generation_tokens = df["generation_tokens"].sum()
        output_token_throughput = total_generation_tokens / total_time
        total_token_throughput = (total_prompt_tokens + total_generation_tokens) / total_time

        # TTFT stats (in milliseconds)
        ttft_ms = df["ttft"] * 1000
        mean_ttft = ttft_ms.mean()
        median_ttft = ttft_ms.median()
        p99_ttft = np.percentile(ttft_ms, 99)

        # Time per Output Token calculation (excluding first token)
        df['tpot'] = ((df['generation_time'] - df['ttft']) / (df['generation_tokens'] - 1)) * 1000
        tpot = df['tpot'].replace([float('inf'), -float('inf'), np.nan], np.nan).dropna()
        mean_tpot = tpot.mean()
        median_tpot = tpot.median()
        p99_tpot = np.percentile(tpot, 99)

        # Inter-token Latency
        df['itl'] = (df['generation_time'] / df['generation_tokens']) * 1000
        itl = df['itl'].replace([float('inf'), -float('inf'), np.nan], np.nan).dropna()
        mean_itl = itl.mean()
        median_itl = itl.median()
        p99_itl = np.percentile(itl, 99)

        print("============ Serving Benchmark Result ============")
        print(f"Successful requests:                     {finished_requests:<10}")
        print(f"Benchmark duration (s):                  {total_time:.2f}      ")
        print(f"Total input tokens:                      {total_prompt_tokens:<10}")
        print(f"Total generated tokens:                  {total_generation_tokens:<10}")
        print(f"Request throughput (req/s):              {request_throughput:.2f}      ")
        print(f"Output token throughput (tok/s):         {output_token_throughput:.2f}    ")
        print(f"Total Token throughput (tok/s):          {total_token_throughput:.2f}    ")
        print("---------------Time to First Token----------------")
        print(f"Mean TTFT (ms):                          {mean_ttft:.2f}     ")
        print(f"Median TTFT (ms):                        {median_ttft:.2f}     ")
        print(f"P99 TTFT (ms):                           {p99_ttft:.2f}     ")
        print("-----Time per Output Token (excl. 1st token)------")
        print(f"Mean TPOT (ms):                          {mean_tpot:.2f}     ")
        print(f"Median TPOT (ms):                        {median_tpot:.2f}     ")
        print(f"P99 TPOT (ms):                           {p99_tpot:.2f}     ")
        print("---------------Inter-token Latency----------------")
        print(f"Mean ITL (ms):                           {mean_itl:.2f}     ")
        print(f"Median ITL (ms):                         {median_itl:.2f}     ")
        print(f"P99 ITL (ms):                            {p99_itl:.2f}     ")
        print("==================================================")

    return buf.getvalue()

def process_output(filename: str, **kwargs):
    df = pd.read_csv(filename)
    summary_str = ProcessSummary(df, pending_queries=0)

    filename_without_parent_or_ext = os.path.splitext(os.path.basename(filename))[0]
    timestamp = datetime.now().strftime("%Y%m%d-%H%M")
    results_path = f"4-latest-results/{filename_without_parent_or_ext}-{timestamp}.results"

    # Read bench-spec.yaml and filter out lines with hf_token
    bench_spec_content = ""
    if os.path.exists("bench-spec.yaml"):
        with open("bench-spec.yaml", "r") as spec_file:
            bench_spec_content = "".join(
                line for line in spec_file if "hf_token" not in line
            )
    else:
        print("bench-spec.yaml not found in summarize.py")

    with open(results_path, "w") as f:
        # Write the timestamp
        f.write(f"Timestamp: {timestamp}\n")
        # Write the summary statistics
        f.write(summary_str)
        # Write the specific workload for this set of statistics
        f.write("\n==================== Workload config ======================\n")
        for k, v in kwargs.items():
            f.write(f"{k}: {v}\n")
        f.write("===========================================================\n")
        # Write the bench-spec.yaml content
        if bench_spec_content:
            f.write("\n==================== bench-spec.yaml ======================\n")
            f.write(bench_spec_content)
            f.write("\n===========================================================\n")

    print(f"Performance summary saved to {results_path}")

    # Save a copy of the results file to ~/srv/runner-db/
    print(f"Saving results to ~/srv/runner-db/{filename_without_parent_or_ext}-{timestamp}.results")
    runner_db_path = os.path.expanduser("~/srv/runner-db/")
    os.makedirs(runner_db_path, exist_ok=True)
    runner_db_file = os.path.join(runner_db_path, f"{filename_without_parent_or_ext}-{timestamp}.results")

    # Copy the contents to the new location
    with open(results_path, "r") as src, open(runner_db_file, "w") as dst:
        dst.write(src.read())
    print(f"Results saved to ~/srv/runner-db/{filename_without_parent_or_ext}-{timestamp}.results")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python summarize.py <path_to_csv> [key=value ...]")
        sys.exit(1)

    filename = sys.argv[1]
    raw_kwargs = sys.argv[2:]

    def parse_value(val):
        try:
            return eval(val, {}, {})
        except:
            return val

    kwargs = {}
    for arg in raw_kwargs:
        if "=" in arg:
            key, val = arg.split("=", 1)
            kwargs[key] = parse_value(val)

    process_output(filename, **kwargs)
