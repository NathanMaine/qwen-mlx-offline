# Pinned versions

Every number in [docs/BENCHMARKS.md](docs/BENCHMARKS.md) was produced by exactly
this combination. It is written down because two things in this stack move
underneath you:

- **`mlx-community` re-quantizes in place.** A repo id is not a version. Pulling
  `Qwen3.8-27B-4bit` today and in three months can hand you different weights
  under the same name, with no warning and no changed path.
- **MLX ships fast.** `pip install -U mlx-vlm` resolves to whatever is current,
  and the speculative-decoding path in particular is young code.

Neither is a criticism — that pace is why this works at all. But a repo whose
value is measured numbers should be able to reproduce them, so here are the
exact inputs.

## Models

| Build | Repo | Revision | Size |
|---|---|---|---|
| 4-bit target | `mlx-community/Qwen3.8-27B-4bit` | `3e6447f082e89cc7f0bc6e5441afd38dfce760ff` | 16.05 GB |
| 8-bit target | `mlx-community/Qwen3.8-27B-8bit` | `815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9` | 29.50 GB |
| MTP drafter | `mlx-community/Qwen3.8-27B-MTP-4bit` | `b643c01b6d3b094e325edb6ebd832e16c486c575` | 0.24 GB |

All three Apache-2.0. Verified against the Hub API on 2026-08-19 (HTTP 200 with
a matching `id`); sizes are the sum of `*.safetensors`.

Fetch them pinned:

```bash
hf download mlx-community/Qwen3.8-27B-4bit \
  --revision 3e6447f082e89cc7f0bc6e5441afd38dfce760ff \
  --local-dir ~/models/Qwen3.8-27B-4bit

hf download mlx-community/Qwen3.8-27B-MTP-4bit \
  --revision b643c01b6d3b094e325edb6ebd832e16c486c575 \
  --local-dir ~/models/Qwen3.8-27B-MTP-4bit

hf download mlx-community/Qwen3.8-27B-8bit \
  --revision 815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9 \
  --local-dir ~/models/Qwen3.8-27B-8bit
```

Dropping `--revision` gets you whatever is current, which is usually fine and
occasionally is not the thing that was measured.

## Runtime

| Component | Version |
|---|---|
| mlx | 0.32.0 |
| mlx-metal | 0.32.0 |
| mlx-lm | 0.31.3 |
| **mlx-vlm** | **0.6.14** |
| transformers | 5.15.0 |
| Python | 3.14.6 (Homebrew) |
| llama-benchy | 0.4.0 |
| llama.cpp (cross-check only) | build 10472 (7a556b8f9) |

Pin the one that matters:

```bash
~/.venvs/mlx/bin/python -m pip install "mlx-vlm==0.6.14"
```

`qwen-preflight` prints the installed versions so you can see drift without
hunting for it.

## Benchmark machine

Apple **M5 Max**, 128 GB unified, 18 cores (6P + 12E), arm64 native.
macOS 26.5.2 (25F84) at the start of the window, **26.6.1 (25G76)** at the end —
which matters, because the panic behaviour in
[docs/STABILITY.md](docs/STABILITY.md) changed across that update.

The scripts here run on much less. The 4-bit build wants 32 GB and the 8-bit
wants 64 GB. **Throughput on a smaller or older machine will not match these
numbers** — decode is bound by memory bandwidth, and the M5 Max's 614 GB/s
(vendor figure, not independently verified here) is the denominator behind every
t/s in this repo. Treat the tables as "what this machine did", not "what your
machine will do."
