Automation wrapper for linpack

Description:
         The Linpack Benchmark is a measure of a computer's floating-point rate of execution.
         It is determined by running a computer program that solves a dense system of linear
         equations.

Location of useful documentation: https://www.netlib.org/utk/people/JackDongarra/faq-linpack.html
Location of underlying workload: Requires the licensed linpack kit.

Packages required: bc,numactl

To run:
```
[root@hawkeye ~]# git clone https://github.com/redhat-performance/linpack-wrapper
[root@hawkeye ~]# linpack-wrapper/linpack/linpack_run
```


```
Options
linpack Usage:
  --interleave: numactl interleave option

General options
  --home_parent <value>: Our parent home directory.  If not set, defaults to current working directory.
  --host_config <value>: default is the current host name.
  --iterations <value>: Number of times to run the test, defaults to 1.
  --run_user: user that is actually running the test on the test system. Defaults to user running wrapper.
  --sys_type: Type of system working with, aws, azure, hostname.  Defaults to hostname.
  --sysname: name of the system running, used in determining config files.  Defaults to hostname.
  --tuned_setting: used in naming the tar file, default for RHEL is the current active tuned.  For non
    RHEL systems, default is none.
  --usage: this usage message.
```
