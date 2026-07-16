# codex-review

OpenAI Codex's native code-review workflow (`codex review` / `codex exec review`), replicated as a Claude Code plugin with minimum deviation: an isolated `codex-reviewer` subagent carrying the Codex review rubric, four review targets with merge-base parity, and a findings + verdict handoff to the main agent.

## What it does

When the main agent finishes substantial implementation work — or when asked — it dispatches the `codex-reviewer` subagent. The reviewer starts with **no conversation history** (the same isolation as Codex's review child session), receives only a short seed instruction (e.g. *"Review the code changes against the base branch 'main'. The merge base commit for this comparison is `<SHA>`. Run `git diff <SHA>`..."*), investigates the diff itself with read-only git commands, and returns:

    ## Findings

    [P1] Un-padding slices along wrong tensor dimensions — src/ops.py:142-148
      One-paragraph explanation of the affected scenario and why the behavior is wrong.

    ## Verdict

    Overall correctness: patch is incorrect
    Explanation: The P1 breaks inference on batched inputs; must fix before merge.
    Confidence: 0.85

The main agent relays both sections verbatim ("Full review comments:") and can then offer to fix the findings.

## Install

Session-only (no install):

    claude --plugin-dir /path/to/codex-review

Via marketplace (once published):

    /plugin marketplace add SSFSKIM/codex-review
    /plugin install codex-review@codex-review

## Usage

The four review targets, mirroring `codex review`'s CLI modes:

| Say | Native equivalent |
|---|---|
| "review my (uncommitted) changes" | `codex review --uncommitted` |
| "review this branch against main" | `codex review --base main` |
| "review commit abc1234" | `codex review --commit abc1234` |
| "run a code review: only check error handling in src/api" | `codex review "<prompt>"` |

The reviewer also triggers proactively: after the main agent completes substantial multi-file or behavior-changing work, it may dispatch a review before committing.

### Effort levels (v0.2.0)

Every target accepts an effort level: `plain` (default) · `medium` · `high` · `xhigh` · `max`. Say it with the request — "codex review **high** against main", "run a **max**-effort codex review of my changes". Unnamed = `plain`, always.

`plain` is the native-parity path above: one isolated full-rubric reviewer. The higher levels multi-agentify it: lens-partitioned **finder** subagents hunt candidates in parallel with a recall bias (medium: 3 lenses — changed-logic, cross-file contracts, removed behavior; high+: 5, adding security and performance), independent **verifier** subagents judge every candidate against the Codex rubric's eight bug criteria (CONFIRMED / PLAUSIBLE / REFUTED, with quoted evidence), `xhigh` adds a **sweep** finder that hunts only the gaps the first wave left, and `max` requires every severe finding to survive two **adversarial refuters** (unanimity to kill). The output contract is identical at every level; only the machinery scales. Cost scales too — medium ≈ 4–7 subagents, high ≈ 6–12; the agent announces the scale before starting. Full protocol: [`skills/codex-review/references/effort-levels.md`](skills/codex-review/references/effort-levels.md).

Why not just run N copies of the plain reviewer? Because the rubric's precision instruction ("prefer outputting no findings") makes every copy self-censor the *same* borderline candidates — the misses are correlated, and a union of censored sets is still censored. The multi-agent levels instead move that precision gate out of the finders and into independent verification and synthesis, which is where it can't suppress recall.

## How it maps to native Codex

Every element of this plugin is a port of a specific mechanism in the Codex Rust codebase — the rubric system prompt, the verbatim seed-prompt templates, the parent-side merge-base precomputation (`git merge-base HEAD <branch-or-its-ahead-upstream>`), the isolated child session, the tool restrictions, and the verdict handoff. The full mechanism map, the deliberate deviations (hybrid text output instead of the rubric's JSON, justified by what native actually renders), and re-sync instructions live in [`skills/codex-review/references/codex-parity.md`](skills/codex-review/references/codex-parity.md).

## Layout

    .claude-plugin/plugin.json           manifest (+ marketplace.json)
    agents/codex-reviewer.md             the isolated reviewer (Codex rubric port; the plain level)
    agents/codex-finder.md               lens-partitioned candidate finder (medium+)
    agents/codex-verifier.md             independent rubric-standard verifier (medium+)
    skills/codex-review/SKILL.md         parent-side dispatch protocol
    skills/codex-review/scripts/resolve_target.sh    merge-base resolution (merge_base_with_head port)
    skills/codex-review/references/codex-parity.md   mechanism map + deviations + re-sync guide
    skills/codex-review/references/effort-levels.md  multi-agent orchestration protocol (medium+)

## License

MIT for this plugin's original content (see `LICENSE`). The review rubric in `agents/codex-reviewer.md`, the rubric criteria vendored in `agents/codex-verifier.md`, the seed-prompt templates in `skills/codex-review/SKILL.md`, and `resolve_target.sh` derive from OpenAI's Codex CLI and remain under Apache-2.0 — the full license text is vendored at `LICENSES/Apache-2.0.txt` and the required attribution is in `NOTICE`.
