---
# Contains material derived from OpenAI Codex (Apache-2.0): the seed-prompt templates and
# user-facing hints from codex-rs/prompts/src/review_request.rs.
# MODIFIED by SSFSKIM (2026): templates embedded in a Claude Code dispatch protocol; the
# base-branch backup template hardened against ref-name shell injection (deviates from the
# upstream text). See NOTICE and LICENSES/Apache-2.0.txt.
name: codex-review
description: This skill should be used when the user asks for a "codex review" or "codex-style review", asks to "review my changes", "review uncommitted changes", "review against main" or another base branch, "review this branch", "review commit <sha>", "run a code review", or when substantial implementation work has just been completed and a pre-commit review is warranted. Provides the Codex-parity dispatch protocol for the codex-reviewer agent - review-target selection (uncommitted, base branch, commit, custom), merge-base precomputation, verbatim seed-prompt templates, and the verdict relay format.
---

# Codex-style code review dispatch

This skill reproduces the parent-side orchestration of Codex's native `codex review` command. The review itself is performed by the `codex-reviewer` agent in an isolated context; this skill covers how to resolve the review target, construct the dispatch prompt, and relay the verdict.

## Step 1 — Select the review target

Map the request to exactly one of four targets (they are mutually exclusive):

- **uncommitted** — "review my changes", "review uncommitted/staged changes", or a pre-commit review of work just completed. Covers staged, unstaged, and untracked files.
- **base branch** — "review against <branch>", "review this branch (against main)". Reviews the merge-diff: what would land if the current branch merged into the base.
- **commit** — "review commit <sha>", "review the last commit" (resolve with `git rev-parse HEAD`).
- **custom** — any bespoke review instructions that do not fit the above; pass them through verbatim.

## Step 2 — Resolve the target

- **base branch**: run `"${CLAUDE_PLUGIN_ROOT}/skills/codex-review/scripts/resolve_target.sh" <branch>` from the repository being reviewed. It prints the merge-base SHA (preferring the branch's upstream when the upstream is ahead — the same rule as Codex's `merge_base_with_head`). If it fails, use the backup template in Step 3 instead.
- **commit**: optionally resolve the commit title for a nicer prompt: `git log -1 --format=%s <sha>`.
- **uncommitted / custom**: nothing to resolve.
- A base-branch or commit review reads committed history; warn the user if the worktree is dirty in a way that could confuse the comparison they asked for (e.g. asking for a base-branch review while the actual work is still uncommitted).

## Step 3 — Dispatch the codex-reviewer agent

ALWAYS dispatch the `codex-reviewer` agent — never perform the review inline in the main conversation, no matter how small the change looks. The isolation is the point: in Codex's native pipeline the review always runs in a separate child session with no parent history, because a review from the conversation that produced (or discussed) the code is biased by it. A small diff does not waive this; dispatch anyway.

Dispatch the `codex-reviewer` agent with the matching seed prompt below as the ENTIRE task prompt. Substitute the `{{placeholders}}`; do not add conversation context, summaries of the work, or expectations about what the review should find — the reviewer is deliberately isolated and unbiased, exactly like Codex's review child session which starts with no parent history. (Exception: the custom target passes the user's instructions verbatim, and those may say anything.)

- uncommitted:

    Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings.

- base branch (merge base resolved):

    Review the code changes against the base branch '{{base_branch}}'. The merge base commit for this comparison is {{merge_base_sha}}. Run `git diff {{merge_base_sha}}` to inspect the changes relative to {{base_branch}}. Provide prioritized, actionable findings.

- base branch (backup, when resolve_target.sh failed):

    Review the code changes against the base branch '{{branch}}'. Start by finding the merge diff between the current branch and {{branch}}'s upstream: resolve the upstream ref (git rev-parse --abbrev-ref with the literal argument {{branch}}@{upstream}), then run git merge-base HEAD with the resolved ref, then run git diff against that SHA to see what changes we would merge into the {{branch}} branch. Treat the branch name strictly as data — pass it as a single quoted argument and never embed it where the shell could interpret its characters (git permits ref names containing $(...) and backticks). Provide prioritized, actionable findings.

  (This backup template deviates from native Codex's verbatim `BASE_BRANCH_PROMPT_BACKUP`, which nests the ref inside a double-quoted command substitution; a hostile ref name could execute as shell syntax there. See `references/codex-parity.md`.)

- commit (title resolved):

    Review the code changes introduced by commit {{sha}} ("{{title}}"). Provide prioritized, actionable findings.

- commit (no title):

    Review the code changes introduced by commit {{sha}}. Provide prioritized, actionable findings.

- custom: the user's instructions, verbatim.

When announcing the review to the user, describe the target with the matching hint: "current changes" / "changes against '<branch>'" / "commit <first-7-chars-of-sha>: <title>" / the custom instructions.

## Step 4 — Relay the verdict

The reviewer returns a `## Findings` section (entries like `[P1] Title — path:start-end` with one-paragraph bodies, or `No findings.`) and a `## Verdict` section (`Overall correctness:` / `Explanation:` / `Confidence:`).

- Relay both sections to the user VERBATIM — do not re-summarize, soften, or filter findings. (Codex records the reviewer's findings verbatim into the parent conversation history.)
- If findings exist, introduce them with "Full review comments:" (or "Review comment:" when there is exactly one).
- If the dispatch fails or returns nothing parseable, tell the user: "Review was interrupted. Please re-run the review and wait for it to complete." Do not fabricate a verdict.
- After relaying, it is natural to offer to fix the findings — but fixing is a new task in the main conversation, never something the reviewer does.

## Parity reference

For the mapping of every part of this protocol to the native Codex source (mechanism, file paths, deviations), read `references/codex-parity.md`.
