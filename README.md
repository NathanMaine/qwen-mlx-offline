# Qwen 3.8 on a MacBook, Offline, All Day

A complete setup for running **Qwen3.8-27B** locally on Apple Silicon with MLX,
fast enough to actually work with. No internet, no API key, no per-token bill.
Close the lid on a plane and it keeps going.

**48 tokens/second on a laptop.** Two quantisations, one command to switch.
Speculative decoding wired up. Scripts, launchers, and the measurements behind
every number.

```bash
qq "explain this traceback" < error.log     # ask it something
qwen-local-4                                 # agentic coding, 4-bit
qwen-stop                                    # give the RAM back
```

---

## Why this exists

A 27B model that answers at 48 t/s is past the threshold where local stops
being a demo. You can hand it a real codebase, let it run a long agent loop,
and never once think about rate limits, context pricing, or whether the
network is up.

Three things had to be true to get there, and each one took finding out:

1. **The MTP weights are missing from the MLX checkpoint.** Qwen3.8 ships with
   a Multi-Token Prediction head that doubles decode speed. `mlx_vlm.convert`
   strips it. It is published separately as a 253 MB adapter, and almost
   nobody mentions this.
2. **The obvious server cannot use it.** `mlx_lm.server` has a `--draft-model`
   flag that looks right and silently cannot drive an MTP drafter. You need
   `mlx_vlm.server --draft-kind mtp`.
3. **The sampling defaults are wrong.** `mlx_lm.server` decodes greedily on a
   model whose own config asks for temperature 1.0. No warning, just quieter
   answers.

Get all three right and an M5 Max does 34 t/s at 8-bit or 48 t/s at 4-bit. Get
them wrong and you get 15 t/s and wonder why local models feel sluggish.

---

## What you get

| Command | What it does |
|---|---|
| `qq "question"` | Ask the local model. Pipe files in. Streams. |
| `qq -i` | Interactive chat |
| `qwen-local-4` | Qwen Code (agentic) against the 4-bit, ~48 t/s |
| `qwen-local-8` | Qwen Code against the 8-bit, ~30 t/s |
| `qwen-serve start\|stop\|status [4\|8]` | Manage the model server |
| `qwen-stop` | Unload and free the memory, verified |
| `qwen-think on\|off\|low\|medium\|xhigh` | Reasoning toggle |
| `vram` / `vram -w` | What is using GPU memory, live |
| `qwen-bench` | Speed check |
| `qwen-preflight [4\|8]` | Check the machine before you serve |
| `qwen-offline-check [4\|8]` | Prove it runs with the network off |

Plus double-clickable `.command` launchers for the Finder-inclined.

---

## Install

**Requires:** Apple Silicon Mac, macOS 26+, 32 GB unified memory for the 4-bit
or 64 GB for the 8-bit. 128 GB gives you room to run both and still work.

```bash
git clone https://github.com/NathanMaine/qwen-mlx-offline.git
cd qwen-mlx-offline
./install.sh
```

`install.sh` creates a Python venv, installs `mlx-vlm`, symlinks the commands
onto your PATH, and tells you which models to download. It does not download
28 GB behind your back.

### Get the models

```bash
# 4-bit, 16 GB, the everyday one
hf download mlx-community/Qwen3.8-27B-4bit --local-dir ~/models/Qwen3.8-27B-4bit

# the MTP drafter, 253 MB, doubles your speed and works with BOTH quants
hf download mlx-community/Qwen3.8-27B-MTP-4bit --local-dir ~/models/Qwen3.8-27B-MTP-4bit

# 8-bit, 28 GB, optional, for when correctness matters more than speed
hf download mlx-community/Qwen3.8-27B-8bit --local-dir ~/models/Qwen3.8-27B-8bit
```

Then:

```bash
qwen-serve start 4
qq "hello"
```

That is the whole setup. From here it works with the network off.

---

## Measured performance

Apple M5 Max, 128 GB, macOS 26.6.1. Benchmarked with
[llama-benchy](https://github.com/eugr/llama-benchy), 3 runs per cell, idle
GPU, reasoning off, MTP on.

| | 4-bit | 8-bit |
|---|---|---|
| **Token generation** | **47.5 t/s** | **30.2 t/s** |
| Prompt processing | 765 t/s | 609 t/s |
| Token generation @ 8K context | 35.1 t/s | 24.1 t/s |
| Time to first token | 2.7 s | 3.4 s |
| Memory resident | 15.5 GB | 28.1 GB |

**MTP speculative decoding is worth 2.2x** and costs nothing in quality, since
the full model verifies every drafted token:

| | Without MTP | With MTP |
|---|---|---|
| 8-bit | 15.5 t/s | **34.1 t/s** |

Full data, including the llama.cpp comparison and the reasoning-cost
measurements, is in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

---

## Things worth knowing

**Context costs about a quarter of your speed.** Decode falls 26% by 8K tokens
and time-to-first-token climbs to ~14 s. Headline numbers are always depth-0
numbers. Plan long agent sessions accordingly.

**Reasoning does not slow generation, it adds invisible tokens.** Throughput is
identical with thinking on or off (30.26 vs 30.17 t/s). The cost is that
reasoning runs before any visible output and often is not counted in
`completion_tokens`. The same 2-token answer took 5.3 s at `low` effort and
62.0 s at `xhigh`. Use `qwen-think off` for mechanical work.

**4-bit and 8-bit scored identically** on a small quality spot check (5/5 each).
That sample is far too small to call them equivalent, and published guidance
still puts real 4-bit degradation on long, hard reasoning. Treat 4-bit as the
speed option, not a free lunch.

**`mlx_vlm.server` binds `0.0.0.0` by default.** Every script here pins
`127.0.0.1`. Worth remembering if you ever run it by hand.

**Watch your GPU memory on long runs.** Allocation ratchets upward rather than
returning to baseline. See [docs/STABILITY.md](docs/STABILITY.md) before you
leave an agent running overnight.

---

## Other targets

The same Qwen Code setup can point elsewhere when you want it to. These are
included but are not what this repo is about:

- `qwen-spark`, another machine on your LAN. Set `QWEN_SPARK_HOST`.
- `qwen-cloud`, a hosted API, when speed matters more than privacy.

Each prints a coloured banner naming where it runs, so you always know whether
your code is leaving the laptop.

---

## Layout

```
bin/          the commands
launchers/    double-clickable .command files for macOS
docs/         benchmarks, stability notes, configuration reference
VERSIONS.md   pinned model revisions + runtime versions behind every number
install.sh    venv + PATH setup
```

---

## Reproducing the numbers

Model repos are not versions: `mlx-community` re-quantizes in place, so the same
repo id can hand you different weights months apart. [VERSIONS.md](VERSIONS.md)
pins the exact model revisions and runtime versions behind every figure here,
with `hf download --revision` commands to match.

`qwen-preflight` catches the two silent throughput killers before you serve:
running under Rosetta, and a macOS older than 26.6.1 (see
[docs/STABILITY.md](docs/STABILITY.md)).

---

## Credits

This repo is glue around other people's work.

- **[llama-benchy](https://github.com/eugr/llama-benchy)** by
  [eugr](https://github.com/eugr) — the benchmark harness behind every number in
  [docs/BENCHMARKS.md](docs/BENCHMARKS.md). It separates prompt processing from
  token generation, runs a coherence check, and reports mean ± stdev across
  runs, which is the difference between a measurement and a vibe. It also made
  the depth-8192 collapse visible; a single-number benchmark would have let this
  repo publish a 48 t/s headline and never mention that it falls to 35 t/s with
  a filled context. `qwen-bench` is a thin wrapper around it.
- **[ml-explore/mlx](https://github.com/ml-explore/mlx)** — the runtime.
- **[mlx-vlm](https://github.com/Blaizzy/mlx-vlm)** by
  [Blaizzy](https://github.com/Blaizzy) — the only one of the two servers that
  can drive an MTP drafter, which is where the 2-3.5x comes from.
- **[mlx-community](https://huggingface.co/mlx-community)** — the 4-bit, 8-bit
  and MTP-4bit conversions.
- **[Qwen](https://huggingface.co/Qwen/Qwen3.8-27B)** — the base model,
  Apache-2.0.
- **[Unsloth](https://huggingface.co/unsloth)** — the Dynamic V3.0 GGUF used for
  the llama.cpp cross-check.

The kernel-panic issues cited in [docs/STABILITY.md](docs/STABILITY.md) belong
to the people who filed them. They turned "my laptop panicked" into "this is a
known driver bug with a known mitigation."

---

## Licence

MIT. The models have their own licences (Qwen3.8 is Apache 2.0).
