# localrag: constraints for the lead

Copy this file to `docs/BRIEF_NOTES.md` in the target project next to `BRIEF.yaml` (from `localrag-mission.yaml`); the goal points the lead at it. It fixes the machine, the stack and the CLI shape so the planner spends its budget on the application rather than on choosing tools.

## Machine

The reference machine for this run was an ordinary laptop with no usable GPU. Change these values to match yours.

| Item | Value |
|---|---|
| CPU | AMD Ryzen 7 7735U, 8 cores / 16 threads |
| RAM | 15 GB |
| GPU | none usable (integrated only; CPU inference) |
| OS | Windows 11, Git Bash |
| Python | 3.13 via `uv` |

Every model must run on the CPU within that RAM alongside the index and the embedding model. Nothing leaves the machine: no hosted APIs for chat or embeddings.

## Fixed stack

- **Inference:** llama.cpp prebuilt CPU binaries (`llama-server` or `llama-cli`), downloaded by the CLI into a cache directory, never committed.
- **Candidate chat models (GGUF, Q4_K_M):** Qwen2.5-1.5B-Instruct, Qwen2.5-3B-Instruct, Llama-3.2-3B-Instruct. The CLI benchmarks each on the machine and records tokens per second; the fastest model whose eval score is acceptable is the default.
- **Embeddings:** nomic-embed-text-v1.5 GGUF through llama.cpp's embedding endpoint.
- **Index:** sqlite for chunks and metadata, embeddings stored as float32 blobs, cosine similarity in numpy. No vector database.
- **PDF text:** pypdf. Keep page numbers with every chunk.
- **Packaging:** `pyproject.toml` with a `localrag` console script, `uv.lock` committed, `src/localrag/` layout.

## CLI shape

| Command | Does |
|---|---|
| `localrag setup` | Download llama.cpp binaries and the GGUF files into the cache; idempotent. |
| `localrag bench` | Run each candidate chat model on a fixed prompt, print tok/s per model, write the table to `docs/RAG_SETUP.md`. |
| `localrag index [--stats]` | Chunk and embed every PDF under `data/`, write the sqlite index; `--stats` prints chunk and document counts. |
| `localrag ask "<question>"` | Retrieve the top passages, answer with the chat model, print the answer followed by citations as `file p.<page>`. Refuse when no passage clears the similarity threshold. |
| `localrag eval` | Run `eval/questions.yaml` (question, expected substring, expected source) and print the score. |

## Tests policy

- `tests/` uses pytest and runs without the models present: chunking, the sqlite index, cosine ranking, citation formatting and CLI argument parsing are tested against fixtures and a fake inference client.
- One integration test, skipped unless the models are in the cache, runs `ask` end to end against a small fixture PDF.
- `uv run pytest -q` must exit 0 on a clean checkout with no downloads.
- The three `ask` criteria in the brief are answerable only from the PDFs in `data/`; replace the questions and expected book names with ones that match your documents before running.

## Observed result (2026-09-30 run)

| Item | Value |
|---|---|
| Model chosen | Qwen2.5-1.5B-Instruct Q4_K_M at 20.9 tok/s (the 3B models were slower with no eval gain) |
| Index | 4,449 chunks over three PDFs |
| Eval | 10 of 13 questions correct |
| Run | `DONE` in 72 minutes, 288 tool calls, 0.68M uncached tokens plus 12.9M cache reads; 4 tasks, the fourth added by the lead after a weak first eval |
| PR | 2,134 lines added |

The lead added the fourth task on its own after the first eval scored below the rubric, recorded the decision in `docs/decisions.md`, and did not ask.
