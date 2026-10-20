# Partitions, QoS limits and preemption

Snapshot 2026-10-19. Re-check with `scontrol show partition` and `sacctmgr show qos` before relying on a number.

## Hardware and partitions

| | Alpha | Grace (scheduled by alpha's Slurm) | Beta |
|---|---|---|---|
| Login host | `alpha1.empire-ai.org` | same as alpha | `beta.empireai.edu` |
| CPU / OS | x86_64, Rocky Linux 9.4 | aarch64 | aarch64, Ubuntu 24.04 |
| Slurm | 23.02.8 | (alpha's) | 25.05.6 |
| GPU nodes | 18 x 8 H100 80 GB (alphagpu01-18), 6 x 8 H200 (alphagpu19-24), 4 x 8 RTX PRO 6000 Blackwell (alphagpu51-54) | 1 GH200 node (alphagh01) | 72 x 4 B200 (GB200 NVL72), 189 GB HBM3e each, plan for ~185 GB |
| CPU nodes | 1 x86 node, 96 cores (`cpu`) | 60 Grace-Grace nodes (betagg01-60), 144 cores, 490 GB | each GPU node: 144 Arm cores, ~1.5 TB |
| SU rate | 1 SU per GPU-hour | 0.5 SU per node-hour | 2 SU per GPU-hour |

Beta partitions:

| Partition | Nodes | Users | Max time | Default time | Sharing | Allowed QoS |
|---|---|---|---|---|---|---|
| `beta` (default) | 59 | everyone | 7 d | 1 h | exclusive (whole node) | priority, standard, long, burst |
| `beta_test` | 4 | everyone | 2 h | 2 h | shared, MaxMemPerCPU 10,834 MB | test, burst |
| `cdmm` | 9 | one project | 7 d | 1 h | shared | cdmm |

Beta site rules (`job_submit.lua` and QoS):
- `beta` accepts batch jobs only: "no interactive jobs allowed in the 'beta' partition -- please submit interactive
  sessions to beta_test."
- Every QoS except `test` has `MinTRES gres/gpu=4`; a smaller request fails at submission with `QOSMinGRES` /
  `Job violates accounting/QOS policy`.
- The `interactive` QoS is in users' associations but in no beta partition's AllowQos.

Alpha partitions: `alpha` (default, GPU), `grace` (Arm CPU nodes plus alphagh01), `cpu` (one x86 node). Nodes are shared;
default memory 19,800 MB per CPU. Site rules:
- An account is mandatory: "Account must be specified - resubmit with an explicit --account=<...> or -A <...>."
- 1-GPU jobs are routed to the RTX PRO 6000 nodes. For H100/H200 request 2+ GPUs and `--constraint=h100` or `h200`.
- Modules exist (`module avail`: `CUDA/13.1`, `Python/3.10.15`, `apptainer/1.1.9`, ...), plus Pyxis/Enroot.

## QoS tables

Beta (limits per job; `MaxTRES`):

| QoS | Priority | Max wall | GPUs per job | Max running / submitted per user | SU multiplier | Partition |
|---|---|---|---|---|---|---|
| `priority` | 1000 | 24 h | 4-72 | 30 / 50 | 2.0 | beta |
| `test` | 800 | 2 h | 1-8 | 5 / 10 | 0.5 | beta_test |
| `standard` | 500 | 48 h | 4-36 | 30 / 50 | 1.0 | beta |
| `long` | 200 | 7 d | 4-36 | 20 / 30 | 0.5 | beta |
| `interactive` | 500 | 2 h | 4 | 1 / - | 1.0 | none on beta |
| `burst` | 0 | 7 d | 4-36 | 30 / 50 | 0 | system-assigned |

Alpha (limits per user over all running jobs; `MaxTRESPU`):

| QoS | Priority | Max wall | Per-user cap | Max running / submitted | SU multiplier |
|---|---|---|---|---|---|
| `priority` | 1000 | 24 h | 64 GPUs, 45 nodes, 6480 CPUs | 30 / 50 | 2.0 |
| `test` | 800 | 2 h | 8 GPUs, 4 nodes, 576 CPUs | 10 / 20 | 0.5 |
| `standard` | 500 | 48 h | 32 GPUs, 30 nodes, 4320 CPUs | 30 / 50 | 1.0 |
| `long` | 200 | 7 d | 32 GPUs, 15 nodes, 2160 CPUs | 20 / 30 | 0.5 |
| `interactive` | 500 | 2 h | 4 GPUs, 2 nodes | 1 / - | 1.0 |
| `burst` | 0 | 7 d | 32 GPUs, 4 nodes | 30 / 50 | 0 |

## Preemption

`PreemptType=preempt/qos`, `PreemptMode=REQUEUE`. Every paid QoS can preempt `burst`; the preempted job goes back to
the queue. A job is protected for its first 15 minutes (`PreemptExemptTime`). Paid-QoS jobs are never preempted.
`sbatch --test-only` prints `Preempts: <jobid>` when a start would preempt a burst job.

## Limit history worth knowing

- Until 2026-09-25 a beta `priority` job with `--time` above 12 h waited forever with
  `QOSMaxWallDurationPerJobLimit` (likely the `UsageFactorSafe` flag: 2.0 x 12 h hit the 24 h cap). On 2026-09-25 the
  QoS flags were reset to `DenyOnLimit`; priority jobs now run the full 24 h. Old advice that priority means 12 h is
  stale.
- `long` lost its `NoReserve` flag on 2026-10-19.
- `sacctmgr list transactions` shows such admin changes.

## Raw snapshots (2026-10-19)

Beta `sacctmgr -P show qos format=Name,Priority,Flags,MaxWall,MinTRES,MaxTRES,MaxTRESPU,MaxJobsPU,MaxSubmitPU,UsageFactor,Preempt`
(rows `normal`, `benchmark`, `admin`, `cdmm` omitted):

```
Name|Priority|Flags|MaxWall|MinTRES|MaxTRES|MaxTRESPU|MaxJobsPU|MaxSubmitPU|UsageFactor|Preempt
burst|0|NoReserve|7-00:00:00|gres/gpu=4|gres/gpu=36||30|50|0.000000|
priority|1000|DenyOnLimit|1-00:00:00|gres/gpu=4|gres/gpu=72||30|50|2.000000|burst,normal
test|800|DenyOnLimit|02:00:00|gres/gpu=1|gres/gpu=8||5|10|0.500000|burst,normal
interactive|500|DenyOnLimit|02:00:00|gres/gpu=4|gres/gpu=4||1||1.000000|burst,normal
standard|500|DenyOnLimit|2-00:00:00|gres/gpu=4|gres/gpu=36||30|50|1.000000|burst,normal
long|200|DenyOnLimit|7-00:00:00|gres/gpu=4|gres/gpu=36||20|30|0.500000|burst,normal
```

Alpha, same command (the QoS RPI projects use):

```
Name|Priority|Flags|MaxWall|MinTRES|MaxTRES|MaxTRESPU|MaxJobsPU|MaxSubmitPU|UsageFactor|Preempt
priority|1000|DenyOnLimit,OverPartQOS|1-00:00:00|||cpu=6480,gres/gpu=64,node=45|30|50|2.000000|burst
test|800|DenyOnLimit,OverPartQOS|02:00:00|||cpu=576,gres/gpu=8,node=4|10|20|0.500000|burst
standard|500|DenyOnLimit,OverPartQOS|2-00:00:00|||cpu=4320,gres/gpu=32,node=30|30|50|1.000000|burst
long|200|DenyOnLimit,OverPartQOS|7-00:00:00|||cpu=2160,gres/gpu=32,node=15|20|30|0.500000|burst
interactive|500|DenyOnLimit,OverPartQOS|02:00:00|||cpu=288,gres/gpu=4,node=2|1||1.000000|burst
burst|0|NoReserve|7-00:00:00|||cpu=576,gres/gpu=32,node=4|30|50|0.000000|
```
