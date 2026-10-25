# Contributing

## The most useful contribution

Report a demo that lied: `scripts/smoke.sh` printed PASS but the demo was half-baked (a dead button, a blank screen, an error only visible in the console). A false FAIL is just as welcome. Please include:

- `DEMO_SPEC.md`
- the output of `bash scripts/smoke.sh`
- the tail of `.claude/smoke.log`
- your OS, your shell and the output of `claude --version`

Never paste secrets, `.env` contents or private transcripts.

## Making a change

1. Run `bash tests/run.sh`. It is plain bash and makes no model calls.
2. Write the failing test first, then the change.
3. `scripts/smoke.sh` may only get stricter. A change that lets a previously failing demo pass needs a very good reason in the PR.
4. Scripts use the standard library and coreutils only. No new dependencies.
5. Everything must work on Linux and on Windows through Git Bash.
6. Run `/code-review medium` and address or answer the findings before you open the PR.

## Where things are

- `scripts/smoke.sh`: the gate. `scripts/stop_hook.sh`: the Stop hook wrapper. `scripts/init.sh`: the installer.
- `.claude/agents/` and `.claude/commands/`: the four stages.
- `.claude/settings.json`: deny list and the Stop hook.
- `tests/`: one file per component, run by `tests/run.sh`.
- `examples/ideas/`: short ideas to try the pipeline on.
- `examples/acceptance/`: hidden checks for those ideas. They score a finished build against what the idea promises, independently of the smoke spec the builder writes.

Contributions are released under the MIT licence.
