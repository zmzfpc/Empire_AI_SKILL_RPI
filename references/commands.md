# Command reference

## Connecting (from the user's laptop)

First login: `ssh <user>@beta.empireai.edu` asks for the LDAP password, then `Authenticator code:` (TOTP from the
authenticator app set up at onboarding). Then install a key once; home is shared, so it also works on alpha:

```bash
ssh-keygen -t ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@beta.empireai.edu
```

`~/.ssh/config`:

```
Host empire-a
    HostName alpha1.empire-ai.org
    User <user>

Host empire-b
    HostName beta.empireai.edu
    User <user>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
    ServerAliveInterval 60
```

ControlMaster lets later `ssh`/`scp`/`rsync` reuse the first connection for 10 minutes. Beta has several login nodes
behind one name (e.g. `b6-21-s1-mgmt-01`, `b7-39-s1-mgmt-02`); a tmux session lives on one of them, so after
reconnecting `hostname` may differ. Compute nodes are reachable only through Slurm (`srun --jobid=<id> --overlap --pty bash`).

## Who am I, what may I use

| Command | Shows |
|---|---|
| `sacctmgr show user $USER` | default account (what beta uses without `-A`) |
| `sacctmgr show assoc where user=$USER format=Account%24,QOS%46,DefaultQOS%8` | accounts and their QoS |
| `id -Gn \| tr ' ' '\n' \| grep '^rp_'` | project accounts (each is a Unix group) |
| `ls -ld /projects/rp/<pi>/<project>` | project directory and its group |
| `sacctmgr show qos format=Name%12,Priority,MaxWall,MinTRES%14,MaxTRES%14,MaxTRESPU%32,MaxJobsPU,MaxSubmitPU,UsageFactor` | every QoS and its limits |

## The cluster

| Command | Shows |
|---|---|
| `sinfo -s` | partitions, nodes allocated/idle/other/total |
| `sinfo -p beta -t idle` | idle nodes now |
| `scontrol show partition beta` | partition limits, allowed QoS, default time |
| `scontrol show node <node>` | GPUs, memory, state |
| `scontrol show res` | maintenance reservations |

## Submitting

| Command | Does |
|---|---|
| `sbatch job.sbatch` | submit |
| `sbatch --test-only job.sbatch` | validate and estimate start; submits nothing |
| `sbatch -A ... -p ... --qos=... --time=... job.sbatch` | command-line options override `#SBATCH` lines |
| `srun ... --pty bash` / `salloc ...` | interactive (only `beta_test` on beta) |
| `srun --jobid=<id> --overlap --pty bash` | shell inside a running job |

Useful options: `--array=0-99%10`, `--dependency=afterok:<id>`, `--export=ALL,VAR=value`, `--output=%x_%j.out`,
`--requeue --signal=B:USR1@900`.

## Monitoring

| Command | Shows |
|---|---|
| `squeue --me` | jobs, state, pending reason |
| `squeue --me --start` | estimated start times |
| `squeue --me -o "%.8i %.10P %.22j %.9q %.8T %.10M %.10l %.5D %R"` | with QoS and time limit |
| `scontrol show job <id>` | full detail of one job |
| `sacct -X -S today -o JobID,JobName%22,Partition,QOS,AllocTRES%42,Elapsed,State` | today's jobs |
| `sacct -j <id> -o JobID,State,ExitCode,Elapsed,MaxRSS` | outcome of a job and its steps |
| `sacct -j <id> -o JobID,Account,QOS,SubmitLine%120` | how it was submitted, which account paid |
| `seff <id>` | CPU/memory efficiency after the end (no GPU) |

## Changing jobs

| Command | Does |
|---|---|
| `scancel <id>` · `scancel --name=<jobname>` · `scancel -u $USER -t PENDING` | cancel (confirm before broad forms) |
| `scontrol hold <id>` / `scontrol release <id>` | stop / allow a pending job from starting |
| `scontrol update JobId=<id> TimeLimit=04:00:00` | lower a time limit (cannot raise) |
| `scontrol update JobId=<id> QOS=standard` | change QoS of a pending job, then reset `TimeLimit` |
| `scontrol update JobId=<id> Partition=beta_test` | move a pending job |
| `scontrol requeue <id>` | put a running batch job back in the queue (needs `--requeue`) |

## Priority and fairshare

| Command | Shows |
|---|---|
| `sprio -w` | weights |
| `sprio -l -u $USER` / `sprio -j <id>` | factor breakdown of pending jobs |
| `sshare -l -U` | own fairshare factor |
| `sshare -l -a -A rp_<pi>_<project>` | project and its users |

## Usage and SU

| Command | Shows |
|---|---|
| `checksu` · `checksu --period all` · `checksu --all-users` | SU allocated / used / left (ColdFront) |
| `sreport -T gres/gpu -t hours cluster AccountUtilizationByUser users=$USER start=<date> end=now` | raw GPU-hours |
| `scripts/su_estimate.sh <account> [start]` | estimated SU per QoS from sacct |

## Storage

| Command | Shows |
|---|---|
| `df -h /mnt/home /projects /ddn` | pool sizes (beta; alpha has no `/ddn`) |
| `lfs quota -h -u $USER /ddn` | beta scratch quota (5 TB) |
| `du -sh <dir>` | size of a directory (slow on huge trees) |
