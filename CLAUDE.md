# quickship — agent instruction contract

## What this is
quickship is currently an empty repository: as of the scaffold commit it contains no README, manifest or application code, so its purpose cannot be inferred. **Owner: replace this paragraph with a one-paragraph description once code lands.** Until then, agents must not guess at product intent — ask, or work only on the task as literally stated.

## Commands
`scripts/gate.sh` is the single source of truth. It detects the stack from the repo root at run time:

| Detected by | Install | Lint | Test | Build |
|---|---|---|---|---|
| `package.json` + `pnpm-lock.yaml` / `yarn.lock` / `bun.lock*` / (none → npm) | `<pm> install` | `<pm> run lint` | `<pm> run test` | `<pm> run build` |
| `pyproject.toml` or `requirements.txt` (`uv run` prefix if `uv.lock`) | `uv sync` / `pip install -r requirements.txt` | `ruff check .` | `pytest -q` | `uv build` / `python -m build` (only if `[build-system]` present) |

Run everything with:

```bash
bash scripts/gate.sh   # exit 0 = pass, 2 = fail (details on stderr)
```

Verified at scaffold time: only the secrets scan runs, because no stack exists yet. **When the first manifest is added, run the gate, then replace this table with the exact commands that passed.**

## Definition of done
A change is done only when all of these hold:
1. Lint clean.
2. Tests green.
3. Build passes.
4. No secrets committed (no API keys, tokens, private keys or `.env` values in tracked files).

`bash scripts/gate.sh` exiting 0 checks 1–4. A Stop hook runs it automatically.

## Hard rules
- Never merge PRs.
- Never force-push (`--force`, `--force-with-lease`, `+refspec`), rebase shared branches or rewrite published history.
- Never touch production config: `.env*` (other than `*.example`), deployment/infra config (e.g. `vercel.json`, `fly.toml`, `netlify.toml`, `Dockerfile*` used for deploy, `infra/`, `terraform/`, `k8s/`, `.github/workflows/*deploy*`), or hosting/dashboard settings via connectors.
- Never push to `main`. Work on a feature branch.
- When the work is done and the gate passes: open a PR and stop. Do not self-review or merge it; hand it back.

## Subagents
- `worker` (`.claude/agents/worker.md`): implements one bounded task and returns a summary and file paths.
- `reviewer` (`.claude/agents/reviewer.md`): read-only audit against the definition of done; returns PASS or a numbered FAIL list.
