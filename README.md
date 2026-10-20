# Empire AI Skill for RPI

[![GitHub stars](https://img.shields.io/github/stars/zmzfpc/Empire_AI_SKILL_RPI?style=social)](https://github.com/zmzfpc/Empire_AI_SKILL_RPI/stargazers)

A [Claude Code](https://claude.com/claude-code) skill that teaches Claude how to work on the **Empire AI** clusters
as an RPI user:

- **Alpha**: `alpha1.empire-ai.org`, x86 with H100, H200 and RTX PRO 6000 GPUs, plus the Arm `grace` CPU partition
- **Beta**: `beta.empireai.edu`, Arm with GB200 NVL72 GPUs

⭐ **If you like it, please star the repo!**

## What Claude learns

- How to find your `rp_<pi>_<project>` account and always pass `-A` and `--time`.
- How to pick the cluster, partition and QoS (`test`, `standard`, `long`, `priority`, `burst`), and the rules each
  cluster enforces. For example, `beta` only accepts jobs with at least 4 GPUs, and 1-GPU jobs on alpha land on an
  RTX PRO 6000.
- How to run jobs in NGC containers on beta, using ready-made sbatch templates for both clusters.
- How to estimate a job's cost in Service Units before submitting, and check what you have spent (`checksu`,
  ColdFront).
- How to read job priority and fairshare (`sprio`, `sshare`).
- How to decode pending reasons and submission errors.
- GB200-specific fixes for page cache stuck in GPU memory and for the `beta_test` CPU/memory mismatch.

## Install

Run this where Claude Code runs, usually an Empire AI login node. Your home directory is the same on alpha and beta,
so one install covers both clusters.

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/zmzfpc/Empire_AI_SKILL_RPI.git ~/.claude/skills/empireai
```

Start a new Claude Code session, and `/empireai` should appear in the slash-command menu.

- **Update:** `git -C ~/.claude/skills/empireai pull`
- **Uninstall:** `rm -rf ~/.claude/skills/empireai`

## Use

The skill loads by itself when you talk about Empire AI, alpha or beta, GB200 jobs, `beta_test`, SU, `checksu` or
ColdFront. You can also call it directly with `/empireai`. Example requests:

- "Run a 1-GPU smoke test of `train.py` on beta."
- "Turn this script into a 24-hour whole-node job on beta."
- "Why is job 214652 still pending?"
- "How many SU will a 12-hour `priority` job on one beta node cost?"
- "How much SU has my project used this month?"

Before Claude submits anything, it shows you the partition, QoS, GPUs, time limit and worst-case SU, and checks the
job with `sbatch --test-only`. Submitting spends your project's SU, so Claude asks before choosing `priority` or
before choosing between several project accounts.

## Contents

```
SKILL.md                  main instructions (Claude reads this first)
references/               QoS and partition tables, priority and fairshare, SU and ColdFront, command reference
templates/                sbatch templates: beta_test_1gpu, beta_node, beta_lane, alpha_h100
scripts/                  numa_exec.sh, reclaim_hbm_pagecache.py (GB200 helpers), su_estimate.sh
```

## Notes

- All cluster facts were checked live on 2026-10-19. Limits change, so the skill tells Claude to trust live command
  output over its notes.
- This is an unofficial community project, not affiliated with Empire AI or RPI. For cluster problems, contact the
  Empire AI help desk (`empireai.freshdesk.com`).
- License: Apache-2.0.
