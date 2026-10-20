#!/bin/bash
# Full-node production job on the beta partition: one GB200 node, 4 B200, torchrun.
# Cost: 4 GPUs x 24 h x 2 SU x 1.0 (standard) = at most 192 SU.  The whole node is billed.
#SBATCH --job-name=train
#SBATCH --account=rp_<pi>_<project>
#SBATCH --partition=beta
#SBATCH --qos=standard                 # 1x SU, up to 48 h; long = 0.5x up to 7 d; priority = 2x up to 24 h
#SBATCH --nodes=1
#SBATCH --gres=gpu:4                   # whole node; every QoS on beta requires >= 4 GPUs
#SBATCH --time=24:00:00
#SBATCH --output=%x_%j.out

srun --container-image='nvcr.io#nvidia/pytorch:26.02-py3' \
     --container-mounts=/mnt/home/$USER:/mnt/home/$USER,/projects:/projects \
     --container-workdir="$PWD" \
     torchrun --nproc_per_node=4 train.py
rc=$?
exit $rc
