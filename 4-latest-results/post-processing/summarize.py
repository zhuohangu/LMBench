import pandas as pd
import sys
from typing import Optional
import os
def ProcessSummary(
    df: pd.DataFrame,
    start_time: Optional[float] = None,
    end_time: Optional[float] = None,
    pending_queries: int = 0,
    qps: Optional[float] = None,
) -> pd.DataFrame:
    # Filter rows based on launch/finish times
    if start_time is not None and end_time is not None:
        launched_queries = len(df.query(f"{start_time} <= launch_time <= {end_time}"))
        df = df.query(f"{start_time} <= finish_time <= {end_time}")
    else:
        launched_queries = len(df)

    print(
        f"Launched queries: {launched_queries}, "
        f"pending queries: {pending_queries}, "
        f"finished queries: {len(df)}"
    )

    if qps is None:
        qps = 0.0

    if start_time is None:
        start_time = df["launch_time"].min()
    if end_time is None:
        end_time = df["finish_time"].max()

    total_time = end_time - start_time
    total_requests = launched_queries + pending_queries
    finished_qps = len(df) / total_time
    _qps = total_requests / total_time

    total_prompt_tokens = df["prompt_tokens"].sum()
    total_generation_tokens = df["generation_tokens"].sum()
    average_prefill_speed = total_prompt_tokens / total_time
    average_generation_speed = total_generation_tokens / total_time
    average_generation_speed_per_request = (
        df["generation_tokens"] / df["generation_time"]
    ).replace([float('inf'), -float('inf')], float('nan')).dropna().mean()
    average_ttft = df["ttft"].mean()

    df = df[df['generation_tokens'] != 0].copy()
    df['ratio'] = df['generation_time'] / df['generation_tokens']
    average_ratio = df['ratio'].mean()

    print("\n==================== Performance summary ======================")
    print(f"  \033[33mQPS: \033[32m{qps:.4f} reqs/s\033[0m")
    print(f"  \033[33mProcessing speed: \033[32m{finished_qps:.4f} reqs/s\033[0m")
    print(f"  \033[33mRequests on-the-fly: {pending_queries}\033[0m")
    print(f"  \033[33mInput tokens per second: \033[32m{average_prefill_speed:.4f} tokens/s\033[0m")
    print(f"  \033[33mOutput tokens per second: \033[32m{average_generation_speed:.4f} tokens/s\033[0m")
    print(f"  \033[33mAverage generation throughput (per request): \033[32m{average_generation_speed_per_request:.4f} tokens/req/s\033[0m")
    print(f"  \033[33mAverage TTFT: \033[32m{average_ttft:.4f}s\033[0m")
    print(f"  Time range: {start_time} - {end_time} ({total_time:.2f}s)")
    print("  Average generation_time / generation_tokens (approx. Inter-Token Latency):", average_ratio)
    print("===============================================================\n")

    return df


def process_output(filename: str):
    df = pd.read_csv(filename)
    summary_df = ProcessSummary(df, pending_queries=0)
    filename_without_parent_or_ext = os.path.splitext(os.path.basename(filename))[0]
    print(f"filename: {filename}, filename_without_parent_or_ext: {filename_without_parent_or_ext}")
    # this path is relative to the parent process run-bench.py
    summary_df.to_csv(f"4-latest-results/ttft-itl-{filename_without_parent_or_ext}.csv", index=False)
    print(f"Filtered summary saved to 4-latest-results/ttft-itl-{filename_without_parent_or_ext}.csv")

# Allow running from command line
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python summarize.py <path_to_csv>")
        sys.exit(1)
    process_output(sys.argv[1])
