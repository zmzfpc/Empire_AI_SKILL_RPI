#!/bin/bash
# Run one payload script inside an NGC container on one 4-GPU GB200 node, with the GB200 fixes built in.
# The #SBATCH defaults are the test lane; options on the command line override them:
#   sbatch -A rp_<pi>_<project> --job-name=<name> beta_lane.sbatch runs/<dir>/run.sh
#   sbatch -A rp_<pi>_<project> -p beta --qos=standard --time=12:00:00 --job-name=<name> \
#          --export=ALL,MODE=<x> beta_lane.sbatch runs/<dir>/run.sh
# Needs numa_exec.sh and reclaim_hbm_pagecache.py in $TOOLS (default: <submit dir>/tools).
# IMAGE overrides the container, e.g. --export=ALL,IMAGE='nvcr.io#nvidia/vllm:26.07-py3'.
#SBATCH --account=rp_<pi>_<project>
#SBATCH --partition=beta_test
#SBATCH --qos=test
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:4
#SBATCH --cpus-per-task=64
#SBATCH --mem=640G                     # <= 64 x 10,834 MB, the beta_test per-CPU memory cap
#SBATCH --time=02:00:00
#SBATCH --output=%x_%j.out
set -uo pipefail
RUN=${1:?usage: sbatch beta_lane.sbatch <payload script>}
TOOLS=${TOOLS:-$SLURM_SUBMIT_DIR/tools}
IMAGE=${IMAGE:-nvcr.io#nvidia/pytorch:26.02-py3}
echo "JOB $SLURM_JOB_ID node=$(hostname) run=$RUN start=$(date -Is)"
# If --mem ever exceeds cpus x 10,834 MB on beta_test, Slurm raises SLURM_CPUS_PER_TASK (64 -> 73 for 768G) but
# keeps SLURM_TRES_PER_TASK=cpu=64, and every inner srun dies with "cpus-per-task set by two different
# environment variables".  Drop the stale one and pass the real count explicitly.
unset SLURM_TRES_PER_TASK
# Evict file page cache that an earlier job left in GPU HBM (host python, GPUs visible; busy GPUs are skipped).
srun -n1 --cpus-per-task="$SLURM_CPUS_PER_TASK" python3 -u "$TOOLS/reclaim_hbm_pagecache.py" || true
# numa_exec.sh binds memory to the CPU NUMA nodes so new page cache stays out of HBM.
srun -n1 --cpus-per-task="$SLURM_CPUS_PER_TASK" --container-image="$IMAGE" \
  --container-mounts=/mnt/home/$USER:/mnt/home/$USER,/projects:/projects \
  --container-workdir="$SLURM_SUBMIT_DIR" \
  bash "$TOOLS/numa_exec.sh" bash "$RUN"
rc=$?
echo "JOB_DONE rc=$rc $(date -Is)"
exit $rc
