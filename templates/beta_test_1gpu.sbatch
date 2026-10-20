#!/bin/bash
# First beta job: 1 B200 on the shared test lane, inside the NGC PyTorch container.
# Expected output: aarch64 <torch version> 1 NVIDIA GB200.  Cost: at most 1 x 0.25 h x 2 x 0.5 = 0.25 SU.
#SBATCH --job-name=hello_gpu
#SBATCH --account=rp_<pi>_<project>    # your ColdFront project account
#SBATCH --partition=beta_test          # the test lane (4 shared nodes)
#SBATCH --qos=test                     # 0.5x SU, 2 h max, 1-8 GPUs
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=160G                     # <= 16 x 10,834 MB, so Slurm does not raise the CPU count
#SBATCH --time=00:15:00                # always set it (default on beta is 1 h)
#SBATCH --output=%x_%j.out

# Beta has no system PyTorch: the work runs inside an NGC container (Pyxis/Enroot).
srun --container-image='nvcr.io#nvidia/pytorch:26.02-py3' \
     --container-mounts=/mnt/home/$USER:/mnt/home/$USER \
     --container-workdir="$PWD" \
     python -c "import platform, torch; print(platform.machine(), torch.__version__, torch.cuda.device_count(), torch.cuda.get_device_name(0))"
