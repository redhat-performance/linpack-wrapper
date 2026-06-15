# Intel LINPACK Benchmark Wrapper

## Description

This wrapper facilitates the automated execution of the Intel LINPACK benchmark. LINPACK is a standard measure of a computer's floating-point rate of execution, determined by solving a dense system of linear equations. Performance is reported in GFLOPS (billions of floating-point operations per second).

The wrapper provides:
- Automated LINPACK execution with CPU topology-aware configuration.
- Automatic detection of sockets, cores, and hyperthreading.
- Per-socket and multi-socket thread scaling.
- NUMA interleave control via numactl.
- Result collection, processing, and verification.
- CSV and JSON output formats.
- System configuration metadata capture.
- Integration with test_tools framework.
- Optional Performance Co-Pilot (PCP) integration.

## Command-Line Options

```
Linpack Options:
  --interleave <value>: numactl interleave option. Defaults to "all".

General test_tools options:
  --home_parent <value>: Parent home directory. If not set, defaults to current working directory.
  --host_config <value>: Host configuration name, defaults to current hostname.
  --iterations <value>: Number of times to run the test, defaults to 1.
  --run_user: User that is actually running the test on the test system. Defaults to current user.
  --sys_type: Type of system working with (aws, azure, hostname). Defaults to hostname.
  --sysname: Name of the system running, used in determining config files. Defaults to hostname.
  --tuned_setting: Used in naming the results directory. For RHEL, defaults to current active tuned profile.
      For non-RHEL systems, defaults to 'none'.
  --use_pcp: Enable Performance Co-Pilot monitoring during test execution.
  --tools_git <value>: Git repo to retrieve the required tools from.
      Default: https://github.com/redhat-performance/test_tools-wrappers
  --usage: Display this usage message.
```

## What the Script Does

The `linpack_run` script performs the following workflow:

1. **Environment Setup**:
   - Clones the test_tools-wrappers repository if not present (default: ~/test_tools).
   - Sources error codes and general setup utilities.

2. **Package Installation**:
   - Installs required dependencies via package_tool.
   - Dependencies are defined in linpack.json for different OS variants (RHEL, Ubuntu, SLES, Amazon Linux).

3. **Hardware Detection**:
   - Detects CPU count, cores per socket, threads per core, and number of sockets.
   - Identifies hyperthreading configuration and socket-to-CPU mappings.
   - Determines NUMA topology for memory interleaving.

4. **LINPACK Binary Setup**:
   - Copies the pre-built `xlinpack_xeon64` binary from the `uploads/` directory.
   - Uses a `linpack.dat` configuration file to define problem size (default: N=20000).

5. **Test Execution**:
   - Runs LINPACK across socket configurations, scaling from single-socket to all sockets.
   - Handles both hyperthreaded and non-hyperthreaded configurations separately.
   - Uses `numactl --interleave` for memory placement control.
   - Sets `OMP_NUM_THREADS` and `GOMP_CPU_AFFINITY` for thread binding.
   - Executes for the specified number of iterations per configuration.

6. **Data Collection**:
   - Captures system configuration (CPU, memory, NUMA topology, kernel version).
   - Records LINPACK configuration parameters and thread/socket settings.
   - Logs timestamps for test runs.
   - Optionally records PCP performance data.

7. **Result Processing**:
   - Extracts performance metrics (GFLOPS) from LINPACK output.
   - Generates CSV files with configuration and performance data.
   - Creates JSON output for verification.
   - Validates results against Pydantic schema.

8. **Verification**:
   - Validates results against Pydantic schema (results_schema.py).
   - Ensures all required fields are present and valid.
   - Uses csv_to_json and verify_results from test_tools.

9. **Output**:
   - Saves all raw output files, processed CSV/JSON, and system metadata.
   - Optionally saves PCP performance data.
   - Archives results to configured storage location.

## Dependencies

Location of underlying workload: Requires the licensed Intel LINPACK binary (`xlinpack_xeon64`). The binary must be placed in the `uploads/` directory as `xlinpack_xeon64-NEW`.

Location of useful documentation: https://www.netlib.org/utk/people/JackDongarra/faq-linpack.html

**Packages required**:
- RHEL: bc, numactl, perf, unzip, git, zip
- Ubuntu: unzip, zip
- Amazon Linux: bc, unzip, zip
- SLES: bc, libnuma1, git, unzip, zip

To run:
```bash
git clone https://github.com/redhat-performance/linpack-wrapper
cd linpack-wrapper/linpack
./linpack_run
```

## The LINPACK Benchmark

Intel LINPACK solves a dense system of linear equations:

**Ax = b**

Where:
- **A** is an N x N matrix of double-precision floating-point numbers
- **x** and **b** are vectors of length N
- The benchmark measures the time to solve for x using LU factorization

### Key Parameters (linpack.dat)

1. **Problem Size (N)**: The dimension of the matrix. Default is 20000. Larger values use more memory and take longer but can achieve higher performance.

2. **Leading Dimension**: Slightly larger than N (default: 20016) to avoid cache conflicts during matrix operations.

3. **Alignment**: Memory alignment in KBytes (default: 4) for optimal cache line usage.

### Thread and Socket Scaling

The wrapper automatically runs LINPACK across multiple configurations:

- **Non-hyperthreaded systems**: Runs per-socket, then progressively adds sockets.
- **Hyperthreaded systems**: Runs with non-hyperthread cores first, then with hyperthread pairs, scaling across sockets.

Thread affinity is controlled via `GOMP_CPU_AFFINITY` to pin threads to specific cores.

### Performance Metric

LINPACK reports performance in **GFLOPS** (billions of floating-point operations per second). Higher values indicate better floating-point computational capability.

## Output Files

The results directory (`linpack_results/`) contains:

- **results_linpack.csv**: CSV file with LINPACK configuration and performance metrics per socket/thread configuration.
- **results_linpack.json**: JSON output generated from the CSV for verification.
- **linpack.out.\***: Raw output files from individual LINPACK runs, including CPU affinity and GFLOPS results.
- **test_results_report**: Overall test pass/fail status.
- **hw_info.out**: System hardware metadata (CPU info, memory, NUMA topology, kernel version).
- **PCP data** (if --use_pcp option used): Performance Co-Pilot monitoring data.

## Examples

### Basic run with defaults
```bash
./linpack_run
```
This runs with:
- numactl interleave across all NUMA nodes
- 1 iteration
- Automatic socket/thread scaling based on detected hardware

### Run with specific NUMA interleave
```bash
./linpack_run --interleave 0,1
```
Interleaves memory across NUMA nodes 0 and 1 only.

### Run multiple iterations
```bash
./linpack_run --iterations 3
```
Runs the benchmark 3 times per thread/socket configuration.

### Run with PCP monitoring
```bash
./linpack_run --use_pcp
```
Collects Performance Co-Pilot data during the run.

### Combination example
```bash
./linpack_run --iterations 5 --interleave all --use_pcp
```
Runs 5 iterations per configuration with NUMA interleave across all nodes and PCP monitoring.

## Result Schema

The Pydantic validation schema (`results_schema.py`) defines the following fields:

| Field | Type | Description |
|-------|------|-------------|
| ht_config | str | Hyperthreading configuration (e.g., hyper_no, ht_yes_1_socket_nh) |
| sockets | int (>0) | Number of sockets used |
| threads | int (>0) | Number of threads used |
| unit | str | Performance unit (GFLOPS) |
| MB_per_sec | int (>0) | Throughput in the reported unit |
| cpu_affin | str | CPU affinity string used for the run |
| Start_Date | datetime | Test start timestamp |
| End_Date | datetime | Test end timestamp |

## Return Codes

The script uses standardized error codes from test_tools error_codes:
- **0**: Success
- **101**: Git clone failure
- **E_GENERAL**: General execution errors (binary not found, test execution failures, validation failures).
- **E_USAGE**: Invalid usage/arguments
- **E_PARSE_ARGS**: Argument parsing errors

## Notes

### Licensed Binary
LINPACK requires a pre-built Intel binary (`xlinpack_xeon64`). This binary is not included in the repository and must be obtained separately and placed as `uploads/xlinpack_xeon64-NEW` relative to the working directory.

### Architecture Support
This wrapper targets x86_64 Intel Xeon systems. The binary name (`xlinpack_xeon64`) reflects this architecture requirement.

### NUMA Interleave
The `--interleave` option controls how memory is distributed across NUMA nodes via `numactl --interleave`. The default value of "all" distributes memory round-robin across all available NUMA nodes, which is generally optimal for LINPACK's memory access patterns.

### Hyperthreading Behavior
The wrapper automatically detects hyperthreading and tests multiple configurations:
- With HT: Tests non-HT cores only, then HT pairs, across increasing socket counts.
- Without HT: Tests all cores per socket, then scales across sockets.

This provides a comprehensive view of performance across different threading configurations.

### Performance Tips
- Run multiple iterations to verify consistency.
- Ensure system is idle (no other workloads) for best results.
- Disable CPU frequency scaling (use performance governor) for reproducible results.
- Consider the active tuned profile on RHEL systems.
- Custom `linpack.dat` files can be placed per-host using the host_config mechanism.
