# Configuration reference

Every script reads environment variables, so nothing needs editing.

## Server

| Variable | Default | What it does |
|---|---|---|
| `QWEN_QUANT` | `8` | Which quant `qwen-serve start` loads |
| `QWEN_MODEL` | `~/models/Qwen3.8-27B-{QUANT}bit` | Target model path |
| `QWEN_DRAFT_MODEL` | `~/models/Qwen3.8-27B-MTP-4bit` | MTP drafter |
| `QWEN_PORT` | `8080` | Listen port (loopback only) |
| `QWEN_NO_MTP` | unset | Set to disable speculative decoding |
| `QWEN_KV_SIZE` | `262144` | `--max-kv-size`, must exceed prompt + max_generation |
| `QWEN_KV_BITS` | `8` | KV cache quantisation; the real memory saver |
| `QWEN_NO_KV_GUARD` | unset | Set to drop both KV flags entirely |

## Client (`qq`)

| Flag | Default | Notes |
|---|---|---|
| `-i` | | Interactive multi-turn |
| `--think` | off | Reasoning on; output goes to stderr so pipes stay clean |
| `--effort` | `low` | `low`, `medium`, `xhigh`. See the warning below |
| `-m N` | 4096, or 32768 with `--think` | Max tokens |
| `-s TEXT` | | System prompt |

`qq` reads stdin, so `git diff | qq "review this"` works.

## Other targets

| Variable | Used by |
|---|---|
| `QWEN_SPARK_HOST` | `qwen-spark`, required, no default |
| `QWEN_SPARK_PORT` | `qwen-spark`, default `8000` |
| `QWEN_SPARK_MODEL` | `qwen-spark` |
| `QWEN_CLOUD_MODEL` | `qwen-cloud` |

## Reasoning effort: read this before turning it up

`reasoning_effort` accepts `low`, `medium`, `xhigh` only. Anything else raises
an exception from the chat template.

**The template defaults to `xhigh` whenever thinking is enabled.** Measured
consequences:

- `xhigh` consumed a 3000-token budget and returned **empty content** after
  193 seconds, still reasoning when it ran out
- The same 2-token answer took **5.3 s at `low` and 62.0 s at `xhigh`**
- Both efforts gave the same wrong answer to a day-of-week question

More reasoning is not reliably more accuracy. `qwen-think low` is the default
here for good reason.

## Qwen Code integration

`qwen-local-4` and `qwen-local-8` expect providers in `~/.qwen/settings.json`
pointing at `http://127.0.0.1:8080/v1`, with the model id set to the **absolute
path** of the model directory. The server hot-swaps quants on request in about
2 seconds, so selecting a different model in the client actually changes what
is loaded.

One thing to cap: Qwen Code reserves **64,000 tokens for generation** on every
request, which the server budgets against `--max-kv-size`. Setting
`"max_tokens": 16384` in the provider's `generationConfig` frees ~48k of that
budget for the prompt.
