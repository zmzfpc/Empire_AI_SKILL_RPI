# Job priority and fairshare

Both clusters use Slurm's multifactor priority with identical weights and the Fair Tree fairshare algorithm.
Check with `scontrol show config | grep ^Priority` and `sprio -w`.

## The formula

```
priority = 100000 x QOS_factor + 50000 x FairShare_factor + 25000 x Age_factor + 5000 x JobSize_factor
           (Partition and Assoc weights are 0; minus nice)
```

| Factor | Definition | Points |
|---|---|---|
| QOS | QoS priority / 1000 | priority 100,000 · test 80,000 · standard, interactive 50,000 · long 20,000 · burst 0 |
| FairShare | rank in the fairshare tree (below) | 0-50,000 |
| Age | eligible wait time / 7 days, capped at 1 | +3,571 per day, up to 25,000; held jobs and jobs waiting on a dependency do not age |
| JobSize | about (nodes / 72 + CPUs / 10,368) / 2 on beta | one full node is about 70 points, negligible |

Reading one job: `sprio -l -u $USER` or `sprio -j <id>`. Example (beta, a pending `test` job):

```
  JOBID PARTITION  USER ACCOUNT  PRIORITY SITE AGE ASSOC FAIRSHARE JOBSIZE PARTITION QOSNAME   QOS NICE
 214652 beta_test  <user> rpi_beta   124237    0 251     0     43935      52         0    test 80000    0
```

80,000 (test) + 43,935 (factor 0.8787 x 50,000) + 251 (about 1 h 41 min waiting) + 52 (job size) = 124,237.

## What dominates

| Job | QoS | FairShare | Age | Total |
|---|---|---|---|---|
| A: `priority`, heavily used project (factor 0.10) | 100,000 | 5,000 | 0 | 105,000 |
| B: `standard`, idle project (factor 0.90) | 50,000 | 45,000 | 0 | 95,000 |
| B after 3 days of waiting | 50,000 | 45,000 | 10,714 | 105,714 |
| C: `long`, idle project | 20,000 | 45,000 | 0 | 65,000 |

- The QoS gap between `priority` and `standard` (50,000) equals the whole fairshare range.
- Within one QoS, fairshare decides. Age only matters after days.

## Priority order is not start order

`SchedulerType=sched/backfill`: the scheduler reserves start times for the top pending jobs, and a lower-priority job
starts at once if it fits a gap without delaying those reservations (plans 7 days ahead in 5-minute steps). A
realistic short `--time` therefore starts sooner. `squeue --me --start` shows estimated starts.

## Fair Tree

```
root
|- rpi                    100 shares   <- institution
|  |- rp_<pi>_<project>   100 shares   <- ColdFront project
|  |  |- user A           "parent"     <- users inherit the project's standing
|  |  '- user B           "parent"
|  '- rp_<pi2>_<project2> 100 shares
|- rpi_beta_test          100 shares   (beta early access, top level)
|- columbia, cornell, cuny, mountsinai, nyu, rit, rochester, suny   (100 shares each)
```

Step 1, usage. Every 5 minutes each running job adds `billing x seconds x QoS UsageFactor` to its account.
- billing: beta 24 per GPU (96 per node); alpha `alpha` 1 per CPU + 12 per GPU; `grace` and `cpu` 0.5 per node
  (`TRESBillingWeights` in `scontrol show partition`).
- UsageFactor = the SU multiplier (priority 2, standard and interactive 1, test and long 0.5, burst 0).
- Half-life 14 days (`PriorityDecayHalfLife=14-0`): usage from 2 weeks ago counts 1/2, 4 weeks 1/4.
- Usage rolls up: project = sum of its users, institution = sum of its projects.
- One beta node-hour on `priority` adds 96 x 3600 x 2 = 691,200 units; on `test` 172,800.

Step 2, level fairshare at each level: `LevelFS = S / U`, with S = shares / (own + siblings' shares) (`NormShares`)
and U = usage / (own + siblings' usage) (`EffectvUsage`). Above 1 = under-used its share, below 1 = over-used,
`inf` = no recent usage.

Step 3, rank. Siblings are sorted by LevelFS (highest first), the tree is walked depth first, and users are numbered in
the order reached: `FairShare_factor = rank / number of users`, first reached = 1.0. Order of influence: institution
vs institutions, then project vs the institution's other projects; users with `parent` shares all get their
project's position, so everyone in one project has the same factor.

Institution standing on 2026-10-19 (it moves daily):

| Institution | Beta LevelFS | Alpha LevelFS |
|---|---|---|
| rpi | 0.525 | 0.377 (lowest of all institutions: 26 % of usage on 10 % of shares) |
| rpi_beta_test | 1.201 | n/a |
| columbia | 0.676 | 0.616 |
| cornell | 0.508 | 0.612 |
| cuny | 1.009 | 8.88 |
| nyu | 0.192 | 1.236 |
| rochester | 11.3 | 0.635 |
| suny | 0.183 | 0.607 |

So every RPI job on alpha starts with a fairshare handicap; on beta RPI sits mid-pack.

## What the user can do

- Use `test` and `long` when they fit: half the fairshare usage. Use `priority` only when needed: double.
- Do not hold GPUs idle; on beta the whole node is charged.
- Waiting helps: usage halves every 14 days.

## Reading sshare

```bash
sshare -l -U                          # own rows; FairShare column = the factor
sshare -l | awk 'NR<=2 || /^ [^ ]/'   # top level (institutions)
sshare -l -a -A rp_<pi>_<project>     # the project and its users
```

| Column | Meaning |
|---|---|
| `RawShares` | configured shares (`parent` = use the parent's) |
| `NormShares` | S, share among siblings |
| `RawUsage` | decayed usage units; **not SU** |
| `NormUsage` | fraction of the whole cluster's usage |
| `EffectvUsage` | U, fraction of usage among siblings |
| `LevelFS` | S / U |
| `FairShare` | final factor (user rows only) |
