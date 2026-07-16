# Parity map: this plugin ↔ Codex's native review

This document maps every part of the `codex-review` plugin to the mechanism it replicates in OpenAI's Codex CLI (the Rust codebase, `codex-rs/`). Use it to audit fidelity and to re-sync the plugin when upstream Codex changes.

## The native mechanism in brief

`codex review --base <branch>` (a headless alias for `codex exec review`) flows as: CLI args → `ReviewRequest { target }` → JSON-RPC `review/start` → core `Op::Review` → `resolve_review_request` (turns the abstract target into a short seed instruction; for a base branch it precomputes the git merge-base SHA) → `spawn_review_thread` (builds a restricted turn context, emits review-mode markers) → `ReviewTask` → `run_codex_thread_one_shot` spawns an **isolated child session**: system prompt = the review rubric, **no inherited conversation history**, web search / collaboration tools disabled, approval policy `Never`. The child investigates the diff itself with git commands and emits findings + an overall-correctness verdict in a mandated output format. The parent parses the child's final message tolerantly, records the findings verbatim into its own conversation history (wrapped in a `<user_action>` block so the parent model understands a review happened), and renders them to the user under a "Full review comments:" header.

Key insight: the diff is never injected as data — the reviewer is *told which git commands to run* and gathers context itself. And the output schema is enforced only by the prompt (`final_output_json_schema: None` in native), parsed tolerantly afterward.

## Element-by-element map

| Native element (codex-rs path) | Plugin counterpart | Fidelity |
|---|---|---|
| Review rubric system prompt — `prompts/templates/review/rubric.md`, installed via `base_instructions` (`core/src/tasks/review.rs:118`) | `agents/codex-reviewer.md` body | Verbatim except output-format section (see Deviations) |
| Isolated child session, `initial_history: None` (`core/src/codex_delegate.rs` via `tasks/review.rs:126-137`) | Claude Code subagent — always starts with a fresh context | Exact |
| Seed prompt templates — `prompts/src/review_request.rs:18-32` (`UNCOMMITTED_PROMPT`, `BASE_BRANCH_PROMPT`, `BASE_BRANCH_PROMPT_BACKUP`, `COMMIT_PROMPT[_WITH_TITLE]`) | `SKILL.md` Step 3, verbatim | Exact |
| Parent-side merge-base precompute — `merge_base_with_head` (`git-utils/src/branch.rs:15`): prefer branch upstream when it exists and is ahead, else local branch; `git merge-base HEAD <ref>` | `scripts/resolve_target.sh` | Exact port |
| Backup resolution when merge-base fails — `BASE_BRANCH_PROMPT_BACKUP` | `SKILL.md` backup template + the agent's "TARGET RESOLUTION FALLBACK" section | Exact + belt-and-suspenders |
| Four review targets — `ReviewTarget::{UncommittedChanges, BaseBranch, Commit, Custom}` (`protocol/src/protocol.rs:3398`) | `SKILL.md` Step 1 | Exact |
| Tool restrictions — web search disabled, collab/multi-agent/spawn disabled (`core/src/session/review.rs:22-26`, `tasks/review.rs:107-115`) | Agent frontmatter `tools: ["Read", "Grep", "Glob", "Bash"]` (no WebFetch/WebSearch/Task/Write/Edit) | Equivalent, declaratively stronger |
| Approval policy `Never` (`tasks/review.rs:119`) | Agent "CONDUCT CONSTRAINTS" (read-only commands only) | Approximate — Claude Code subagents inherit the session permission mode; read-only git commands pass in practice |
| `review_model` config, falling back to the parent model (`tasks/review.rs:121-124`) | Agent frontmatter `model: inherit` | Exact parity with `review_model` unset; set `model:` to mirror a configured `review_model` |
| Verdict handoff — child's `TurnComplete.last_agent_message` parsed by the parent (`tasks/review.rs:168-174`) | Subagent's final message returned as the dispatch result | Exact |
| Findings text rendering — `format_review_findings_block` / `render_review_output_text` (`protocol/src/review_format.rs`): "Full review comments:" header, `- Title — path:start-end` + indented body | `SKILL.md` Step 4: relay verbatim under the same headers | Equivalent (relay instead of re-render) |
| Recording into parent history — `exit_review_mode` (`tasks/review.rs:216`) writes findings verbatim as user+assistant messages | The dispatch result lands in the main agent's context; Step 4 forbids re-summarizing | Equivalent |
| Interrupted-review fallback message (`tasks/review.rs:236-239`) | `SKILL.md` Step 4 failure branch, same wording | Exact |
| User-facing hints — `user_facing_hint` (`prompts/src/review_request.rs:110-124`) | `SKILL.md` Step 3 announcement hints | Exact |
| Review-mode UI markers — `EnteredReviewMode`/`ExitedReviewMode` items | None (Claude Code shows its own subagent progress UI) | Cosmetic, not replicated |

## Deviations (each deliberate, logged in the ExecPlan's Decision Log)

1. **Output format is hybrid text, not the rubric's JSON schema.** The agent returns `## Findings` (`[P1] Title — path:start-end` + one-paragraph body) and `## Verdict` (`Overall correctness:` / `Explanation:` / `Confidence:`). Justification: native's own text renderer drops the JSON structure anyway (only title/location/body reach the parent-visible text; `overall_correctness` and confidences are never rendered), and Codex's own first-party skill-ification of this workflow (`codex-rs/skills/src/assets/samples/review-agent/SKILL.md`, used by the app-server's "detached" review delivery) also dropped JSON in favor of `[P1]`-tagged text.
2. **The Verdict block surfaces `Overall correctness:` and `Confidence:`,** which native's text render omits. This carries the rubric's `overall_correctness` / `overall_confidence_score` to the main agent as a machine-greppable line — the plugin's one enrichment.
3. **Per-finding `confidence_score` and the numeric `priority` field are dropped** from the output; priority survives as the `[P0]`–`[P3]` title tag — the same surface native users see.
4. **A "When to invoke" section is appended** to the agent (Claude Code agent convention for dispatch triggering; native's analog is the `Op::Review` dispatch plumbing, which needs no prompt text).
5. **The base-branch backup template is hardened against ref-name shell injection.** Native's `BASE_BRANCH_PROMPT_BACKUP` (`prompts/src/review_request.rs:20`) interpolates the branch name inside a double-quoted command substitution; git accepts ref names containing `$(...)`, which a shell would execute. The plugin's backup template instructs resolving the upstream with the ref passed as a literal quoted argument instead, and the agent's fallback section mandates treating ref names as data. Found by a native `codex exec review` of this very plugin (a [P2]); the same exposure exists upstream.

## Re-sync instructions

When upstream Codex changes, re-check these files and fold differences into the plugin:

- `codex-rs/prompts/templates/review/rubric.md` → `agents/codex-reviewer.md` body (everything above OUTPUT FORMAT should stay verbatim).
- `codex-rs/prompts/src/review_request.rs` → `SKILL.md` Step 3 templates and announcement hints.
- `codex-rs/git-utils/src/branch.rs` (`merge_base_with_head`, `resolve_upstream_if_remote_ahead`) → `scripts/resolve_target.sh`.
- `codex-rs/core/src/tasks/review.rs` + `core/src/session/review.rs` → agent frontmatter restrictions and CONDUCT CONSTRAINTS.
- `codex-rs/skills/src/assets/samples/review-agent/SKILL.md` → compare adaptation choices.
