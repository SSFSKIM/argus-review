# Argus

Multi-agent code review for Claude Code. One isolated reviewer by default; when the diff warrants it, scale through effort levels to a hundred-eyed panel — lens-partitioned finders, independent verifiers, a gap sweep, and adversarial voting. Every review ends in a decisive verdict.

## The method

An Argus review has three properties an in-conversation review lacks:

**Isolation.** The review never runs in the conversation that wrote the code. The reviewer subagent starts with **no conversation history**, receives only a short seed instruction (e.g. *"Review the code changes against the base branch 'main'. The merge base commit for this comparison is `<SHA>`. Run `git diff <SHA>`..."*), and investigates the diff itself with read-only git commands. The conversation that authored the code has no vote on its correctness.

**A decisive verdict.** Every review — at every effort level — returns the same two-section contract:

    ## Findings

    [P1] Un-padding slices along wrong tensor dimensions — src/ops.py:142-148
      One-paragraph explanation of the affected scenario and why the behavior is wrong.

    ## Verdict

    Overall correctness: patch is incorrect
    Explanation: The P1 breaks inference on batched inputs; must fix before merge.
    Confidence: 0.85

The main agent relays both sections verbatim ("Full review comments:") and can then offer to fix the findings. At the multi-agent levels the verdict is deterministic: `patch is incorrect` if and only if a confirmed finding survives verification.

**Effort levels that scale the machinery, never the output.** `plain` (default) · `medium` · `high` · `xhigh` · `max`. The level changes how much independent scrutiny the diff gets; the output contract never changes.

## Install

    /plugin marketplace add SSFSKIM/argus-review
    /plugin install argus-review@argus-review

Session-only (no install):

    claude --plugin-dir /path/to/argus-review

## Usage

Four review targets:

| Say | Reviews |
|---|---|
| "argus review my changes" | uncommitted work (staged, unstaged, untracked) |
| "argus review this branch against main" | the merge-diff against a base branch |
| "argus review commit abc1234" | a single commit |
| "run argus: only check error handling in src/api" | a custom scope |

The reviewer also triggers proactively: after the main agent completes substantial multi-file or behavior-changing work, it may dispatch a review before committing.

### Effort levels

Say the level with the request — "argus review **high** against main", "run a **max**-effort argus review of my changes". Unnamed = `plain`, always.

`plain` is one isolated reviewer carrying the full review rubric. The higher levels multi-agentify it: lens-partitioned **finder** subagents hunt candidates in parallel with a recall bias (medium: 3 lenses — changed-logic, cross-file contracts, removed behavior; high+: 5, adding security and performance), independent **verifier** subagents judge every candidate against a strict eight-criterion bug standard (CONFIRMED / PLAUSIBLE / REFUTED, with quoted evidence), `xhigh` adds a **sweep** finder that hunts only the gaps the first wave left, and `max` requires every severe finding to survive two **adversarial refuters** (unanimity to kill). Cost scales too — medium ≈ 4–7 subagents, high ≈ 6–12; the agent announces the scale before starting. Full protocol: [`skills/argus-review/references/effort-levels.md`](skills/argus-review/references/effort-levels.md).

Why not just run N copies of one reviewer? Because a reviewer tuned for precision ("prefer reporting no findings") self-censors the *same* borderline candidates in every copy — the misses are correlated, and a union of censored sets is still censored. Argus instead moves that precision gate out of the finders and into independent verification and synthesis, which is where it can't suppress recall.

## Layout

    .claude-plugin/plugin.json           manifest (+ marketplace.json)
    agents/argus-reviewer.md             the isolated full-rubric reviewer (the plain level)
    agents/argus-finder.md               lens-partitioned candidate finder (medium+)
    agents/argus-verifier.md             independent rubric-standard verifier (medium+)
    skills/argus-review/SKILL.md         parent-side dispatch protocol
    skills/argus-review/scripts/resolve_target.sh    merge-base resolution
    skills/argus-review/references/effort-levels.md  multi-agent orchestration protocol (medium+)
    skills/argus-review/references/provenance.md     upstream-derivation ledger + re-sync guide

## License

MIT for this plugin's original content (see `LICENSE`). The single-reviewer core adapts Apache-2.0-licensed review-method text from OpenAI's Codex CLI — the review rubric in `agents/argus-reviewer.md`, the bug criteria vendored in `agents/argus-verifier.md`, the seed-prompt templates in `skills/argus-review/SKILL.md`, and the merge-base rule in `resolve_target.sh`. The full Apache-2.0 text is vendored at `LICENSES/Apache-2.0.txt`, the required attribution is in `NOTICE`, and the element-by-element derivation ledger is [`skills/argus-review/references/provenance.md`](skills/argus-review/references/provenance.md).
