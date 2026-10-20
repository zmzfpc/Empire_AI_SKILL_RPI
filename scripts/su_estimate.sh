#!/bin/bash
# Estimate the SU your own jobs cost, per QoS, from sacct.  ColdFront (checksu) is the authority; this is a cross-check.
#   su_estimate.sh <account> [start date, default 2026-10-01 = when SU charging began]
# Run it on the login node of the cluster whose jobs you want: beta (aarch64) bills 2 SU per GPU-hour, alpha (x86_64)
# bills 1 SU per GPU-hour and 0.5 SU per node-hour on the grace partition.  Elapsed time of running jobs is counted
# so far.  For everyone in the project use `checksu --all-users`.
set -euo pipefail
ACCT=${1:?usage: su_estimate.sh <account> [start date YYYY-MM-DD]}
START=${2:-2026-10-01}
case $(uname -m) in aarch64) RATE=2 ;; *) RATE=1 ;; esac
sacct -X -n -P -u "$USER" -A "$ACCT" -S "$START" -E now -o QOS,Partition,AllocTRES,ElapsedRaw | awk -F'|' -v rate="$RATE" '
  function tres(s, key,   m) { if (match(s, key "=[0-9]+")) return substr(s, RSTART + length(key) + 1, RLENGTH - length(key) - 1); return 0 }
  BEGIN { f["priority"]=2; f["standard"]=1; f["interactive"]=1; f["test"]=0.5; f["long"]=0.5; f["burst"]=0 }
  $4 > 0 {
    h = $4 / 3600; q = $1
    if ($2 == "grace") { n = tres($3, "node"); nh[q] += n * h; su[q] += n * h * 0.5 * f[q] }
    else               { g = tres($3, "gres/gpu"); gh[q] += g * h; su[q] += g * h * rate * f[q] }
  }
  END {
    printf "%-12s %12s %12s %10s\n", "QoS", "GPU-hours", "node-hours", "SU"
    for (q in su) { printf "%-12s %12.1f %12.1f %10.1f\n", q, gh[q], nh[q], su[q]; t += su[q] }
    printf "%-12s %12s %12s %10.1f\n", "total", "", "", t
  }'
