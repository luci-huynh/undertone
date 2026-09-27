# Operator protocol

- PLAN.md is the product spec; CODEX_RUNBOOK.md governs execution.
- Before each step, read PLAN.md, applicable AGENTS.md, and docs/PROGRESS.md.
- Perform only one explicitly authorized step ID per turn. Do not prepare later steps or delegate them ahead of approval.
- After every step, including success, failure, or a skipped step, STOP and wait for explicit user confirmation. Full permissions do not authorize moving to another step.
- Report changed files, actual checks and exit codes, pending manual checks, limitations, rollback, and the proposed next step.
- If blocked, request what is needed to finish the current step, not approval to advance.
- Update docs/PROGRESS.md from S04 onward. Never invent PASS results or user approvals.
- Preserve existing work and PLAN.md. Do not stage, commit, push, publish, or recreate the repository without separate authorization.
- Keep translation local through Ollama; never send selected text outside localhost or store/log selected text or translations.
