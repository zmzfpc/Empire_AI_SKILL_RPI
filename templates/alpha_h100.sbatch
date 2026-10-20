#!/bin/bash
# Minimal alpha job on 2 H100.  A 1-GPU job on alpha always lands on an RTX PRO 6000, whatever you ask for.
# Cost: 2 GPUs x 0.25 h x 1 SU x 0.5 (test) = at most 0.25 SU.
#SBATCH --job-name=hello_alpha
#SBATCH --account=rp_<pi>_<project>    # required on alpha: jobs without an account are rejected
#SBATCH --partition=alpha
#SBATCH --qos=test
#SBATCH --gres=gpu:2                   # >= 2 GPUs to stay off the RTX PRO 6000 nodes
#SBATCH --constraint=h100              # or h200
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G                     # alpha nodes are shared: size CPUs and memory
#SBATCH --time=00:15:00
#SBATCH --output=%x_%j.out

# Alpha is x86_64 with modules (module avail: CUDA/13.1, Python/3.10.15, apptainer/1.1.9, ...)
# and the same Pyxis/Enroot --container-image support as beta.
nvidia-smi -L
