---
# Contains material derived from OpenAI Codex (Apache-2.0): the seed-prompt templates and
# user-facing hints from codex-rs/prompts/src/review_request.rs.
# MODIFIED by SSFSKIM (2026): templates embedded in a Claude Code dispatch protocol; the
# base-branch backup template hardened against ref-name shell injection (deviates from the
# upstream text). See NOTICE and LICENSES/Apache-2.0.txt.
name: argus-review
description: This skill should be used when the user asks for an "argus review" or "argus-style review", asks to "run argus" on changes, a branch, or a commit, asks to "review my changes", "review uncommitted changes", "review against main" or another base branch, "review this branch", "review commit <sha>", "run a code review", names an effort level like "argus review high", "argus review medium/xhigh/max", or "maximum-effort argus review", or when substantial implementation work has just been completed and a pre-commit review is warranted. Provides the dispatch protocol for the argus-reviewer agent - effort-level selection (plain default, or the multi-agent medium/high/xhigh/max ladder), review-target selection (uncommitted, base branch, commit, custom), merge-base precomputation, seed-prompt templates, and the verdict relay format.
---

# Argus code review dispatch

This skill is the parent-side orchestration of an Argus review: one isolated reviewer at the plain level, a multi-agent panel at medium and above. The review itself is always performed by isolated subagents; this skill covers how to select the effort level, resolve the review target, construct the dispatch prompt(s), and relay the verdict.

## Step 0 — Select the effort level

Five levels: `plain` (default), `medium`, `high`, `xhigh`, `max`.

- Use the level the request names explicitly ("argus review high", "run a max-effort argus review").
- No level named — including every proactive post-implementation self-review — means `plain`: the single-reviewer path. Thoroughness adjectives alone ("thorough", "deep") do not escalate; if the user seems to want more than plain but named no level, ask or stay at plain.
- A request naming `low` maps to `plain` (this ladder has no low tier; plain is the lightest path).
- `plain` runs one isolated full-rubric reviewer. `medium`/`high`/`xhigh`/`max` run the multi-agent protocol in `references/effort-levels.md`: lens-partitioned finder agents, independent verifiers applying the rubric's bug criteria, a sweep pass at xhigh+, and an adversarial vote on severe findings at max. Announce the level and its approximate subagent scale before starting a medium+ review.

## Step 1 — Select the review target

Map the request to exactly one of four targets (they are mutually exclusive):

- **uncommitted** — "review my changes", "review uncommitted/staged changes", or a pre-commit review of work just completed. Covers staged, unstaged, and untracked files.
- **base branch** — "review against <branch>", "review this branch (against main)". Reviews the merge-diff: what would land if the current branch merged into the base.
- **commit** — "review commit <sha>", "review the last commit" (resolve with `git rev-parse HEAD`).
- **custom** — any bespoke review instructions that do not fit the above; pass them through verbatim.

This skill assumes a POSIX shell (bash/zsh) for `resolve_target.sh` and the quoting rules below. On a Windows session without Git Bash, skip the script and use the base-branch backup template in Step 3 (the reviewer resolves the merge base itself with git), and pass any branch name to the reviewer as plain prose rather than as a shell-quoted argument.

## Step 2 — Resolve the target

- **base branch**: run `"${CLAUDE_PLUGIN_ROOT}/skills/argus-review/scripts/resolve_target.sh" '<branch>'` from the repository being reviewed — substitute the branch name inside the single quotes, and if the name itself contains a single quote, replace each `'` with `'\''` first (the standard POSIX idiom; with it, single-quoting is safe for every character git allows in a ref, including `$(...)`, backticks, `;`, and quotes). It prints the merge-base SHA (preferring the branch's upstream when the upstream is ahead). If it fails, use the backup template in Step 3 instead.
- **commit**: optionally resolve the commit title for a nicer prompt: `git log -1 --format=%s <sha>`.
- **uncommitted / custom**: nothing to resolve.
- A base-branch or commit review reads committed history; warn the user if the worktree is dirty in a way that could confuse the comparison they asked for (e.g. asking for a base-branch review while the actual work is still uncommitted).

## Step 3A — plain: dispatch the argus-reviewer agent

ALWAYS dispatch the `argus-reviewer` agent — never perform the review inline in the main conversation, no matter how small the change looks. The isolation is the point: a review from the conversation that produced (or discussed) the code is biased by it, so the review always runs in a separate agent with no parent history. A small diff does not waive this; dispatch anyway.

Dispatch the `argus-reviewer` agent with the matching seed prompt below as the ENTIRE task prompt. Substitute the `{{placeholders}}`; do not add conversation context, summaries of the work, or expectations about what the review should find — the reviewer is deliberately isolated and unbiased, and starts with no conversation history. (Exception: the custom target passes the user's instructions verbatim, and those may say anything.)

- uncommitted:

    Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings.

- base branch (merge base resolved):

    Review the code changes against the base branch '{{base_branch}}'. The merge base commit for this comparison is {{merge_base_sha}}. Run `git diff {{merge_base_sha}}` to inspect the changes relative to {{base_branch}}. Provide prioritized, actionable findings.

- base branch (backup, when resolve_target.sh failed):

    Review the code changes against the base branch '{{branch}}'. Start by finding the merge diff between the current branch and {{branch}}'s upstream: resolve the upstream ref (git rev-parse --abbrev-ref with the literal argument {{branch}}@{upstream}), then run git merge-base HEAD with the resolved ref, then run git diff against that SHA to see what changes we would merge into the {{branch}} branch. Treat the branch name strictly as data — pass it as a single-quoted argument, escaping any embedded single quote as '\'' first, and never embed it where the shell could interpret its characters (git permits ref names containing $(...), backticks, semicolons, and quotes). Provide prioritized, actionable findings.

  (This backup template hardens the upstream template it derives from, which nests the ref inside a double-quoted command substitution; a hostile ref name could execute as shell syntax there. See `references/provenance.md`.)

- commit (title resolved):

    Review the code changes introduced by commit {{sha}} ("{{title}}"). Provide prioritized, actionable findings.

- commit (no title):

    Review the code changes introduced by commit {{sha}}. Provide prioritized, actionable findings.

- custom: the user's instructions, verbatim.

When announcing the review to the user, describe the target with the matching hint: "current changes" / "changes against '<branch>'" / "commit <first-7-chars-of-sha>: <title>" / the custom instructions.

## Step 3B — medium / high / xhigh / max: run the multi-agent protocol

Read `references/effort-levels.md` and execute it exactly. In brief: dispatch one `argus-finder` agent per lens (each carrying the SAME resolved target seed template from Step 3A plus its lens assignment) in one parallel batch; group returned candidates by location; dispatch one `argus-verifier` agent per group at the level's posture; at xhigh+ dispatch the sweep finder after verification; at max dispatch two adversarial refuters per surviving severe finding; then assemble the output mechanically per the protocol's synthesis rules.

The isolation invariant extends to this path: the orchestrating main agent never judges code inline — it resolves, dispatches, groups, and assembles. Verifier verdicts are binding: do not add findings, soften or reword verifier comments, re-judge a verdict, or drop findings except by the protocol's deterministic rules. For a custom target, the user's instructions ride in every finder dispatch as scope guidance explicitly labeled as data, not instructions.

## Step 4 — Relay the verdict

The review produces a `## Findings` section (entries like `[P1] Title — path:start-end` with one-paragraph bodies, or `No findings.`) and a `## Verdict` section (`Overall correctness:` / `Explanation:` / `Confidence:`). At plain, the argus-reviewer agent returns this block directly; at medium+, the orchestrator assembles the IDENTICAL contract per the synthesis rules in `references/effort-levels.md` (finding bodies verbatim from verifiers, deterministic verdict) — the level changes the machinery, never the output shape.

- Relay both sections to the user VERBATIM — do not re-summarize, soften, or filter findings. (The findings enter the main conversation exactly as written; the relay never editorializes.)
- If findings exist, introduce them with "Full review comments:" (or "Review comment:" when there is exactly one).
- If the dispatch fails or returns nothing parseable, tell the user: "Review was interrupted. Please re-run the review and wait for it to complete." Do not fabricate a verdict.
- After relaying, it is natural to offer to fix the findings — but fixing is a new task in the main conversation, never something the reviewer does.

## Provenance

The single-reviewer core adapts an Apache-2.0-licensed review method; the mechanism map, the deliberate deviations, and the re-sync guide live in `references/provenance.md` (see also `NOTICE`).
