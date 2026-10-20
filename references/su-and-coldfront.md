# Service Units and ColdFront

## Where the balance lives

Slurm has no SU limits (no `GrpTRESMins` on beta). The ledger is ColdFront, <https://coldfront.empireai.edu/>: the
project page shows the allocation, its period and its usage.

- A PI's ColdFront project becomes the Slurm account `rp_<pi>_<project>` on both clusters; members added in ColdFront
  get the account. The same name is a Unix group and the directory `/projects/rp/<pi>/<project>`.
- An allocation runs one year. SU can be requested any time ("Requested SU").
- SU charging started on 2026-10-01; earlier usage was not billed.
- Out of SU: the budget enforcer restricts the project to `burst` (free, lowest priority, preemptable). Running jobs
  are not killed. The PI requests more SU.

## Formula

```
SU = GPU-hours x resource rate x QoS multiplier      (+ storage: TB-months x 8.333)
```

| Resource | Rate |
|---|---|
| Alpha GPU (H100, H200, RTX PRO 6000) | 1 SU per GPU-hour |
| Beta GPU (B200) | 2 SU per GPU-hour |
| Grace-Grace CPU node | 0.5 SU per node-hour |
| Storage (home, projects, scratch) | 8.333 SU per TB-month, up to 100 TB (100 SU per TB-year) |
| QoS multiplier | priority 2, standard and interactive 1, test and long 0.5, burst 0 |

1 SU = $0.50 (RPI FOCI). On partition `beta` the whole node is billed: a job that uses 1 GPU there pays for 4.

| Job | Calculation | SU | USD |
|---|---|---|---|
| beta, 1 node (4 B200), 12 h, `priority` | 4 x 12 x 2 x 2 | 192 | 96 |
| beta, 1 node, 12 h, `standard` | 4 x 12 x 2 x 1 | 96 | 48 |
| beta, 1 node, 12 h, `long` | 4 x 12 x 2 x 0.5 | 48 | 24 |
| beta, 4 GPUs, 2 h, `test` | 4 x 2 x 2 x 0.5 | 8 | 4 |
| beta, 1 GPU, 15 min, `test` | 1 x 0.25 x 2 x 0.5 | 0.25 | 0.13 |
| alpha, 8 x H100, 24 h, `standard` | 8 x 24 x 1 x 1 | 192 | 96 |
| alpha, 1 RTX PRO 6000, 2 h, `test` | 1 x 2 x 1 x 0.5 | 1 | 0.50 |
| grace, 1 node, 10 h, `standard` | 10 x 0.5 x 1 | 5 | 2.50 |
| 2 TB stored for one month | 2 x 8.333 | 16.7 | 8.33 |

Storage: 1 TB kept for a year = 100 SU ($50); 10 TB = 1,000 SU; 50 TB = 5,000 SU. Nothing is purged, so stale
checkpoints keep costing until deleted.

## checksu

Available on both login nodes; prints ColdFront's numbers from a snapshot refreshed about every 15 minutes.

```bash
checksu                              # this month
checksu --period all                 # whole history (months before 2026-10 shown but not billed)
checksu --period 2026-10:2026-12
checksu -p <project>                 # one project
checksu --all-users                  # everyone in the project
checksu --json
```

Output shape (`checksu --period all`):

```
Account:                                  rp_<pi>_<project>
Period:                            all (2026-03 .. 2026-10)
Last Captured:                      2026-10-19 19:15:05 EDT
Allocation 2026-07-28 .. 2027-07-28 (SU used since 2026-10)
  Allocated 14,360.0   Used 0.1   Left 14,359.9
Your SU Used:                                         118.7
Project usage (all users), SU by resource and QOS:
                 test  standard  priority  Total
                 x0.5        x1        x2
  Alpha           0.2         -         -    0.2
  Beta              -       2.8     115.5  118.3
  Grace             -       0.2         -    0.2
  VAST storage      -         -         -    0.0
  TOTAL SU USED   0.2       3.0     115.5  118.7
```

It prints one block per project, but only for projects the user has already used.

## Estimating from Slurm

These see raw usage only; the rate and QoS multiplier must be applied by hand.

```bash
# raw GPU-hours per account
sreport -T gres/gpu -t hours cluster AccountUtilizationByUser users=$USER start=2026-10-01 end=now

# estimated SU per QoS for the user's own jobs (run on the cluster whose jobs you want)
scripts/su_estimate.sh rp_<pi>_<project> 2026-10-01
```

`su_estimate.sh` uses 2 SU per GPU-hour on beta (aarch64 login node), 1 on alpha, and 0.5 per node-hour for the
`grace` partition. Rounding and snapshot timing make small differences from `checksu` normal.
