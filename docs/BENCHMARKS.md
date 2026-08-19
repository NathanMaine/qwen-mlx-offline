# Qwen3.8-27B on Apple M5 Max, Complete MLX Performance Data

Complete measurement record behind the numbers in the README:
4-bit vs 8-bit, reasoning on vs off, MTP speculative decoding, and a
llama.cpp cross-check.

Every number below was measured on the machine described in §1. Figures taken
from external sources are labelled as such. Nothing here is estimated.

**Collection window:** 2026-08-15 → 2026-08-19

---

## 1. Test environment

| | |
|---|---|
| Machine | MacBook Pro, Apple **M5 Max** |
| Memory | **128 GB** unified (no discrete VRAM) |
| CPU | 18 cores, 6 performance + 12 efficiency |
| Architecture | arm64 (native, not Rosetta) |
| OS at start | macOS 26.5.2 (25F84), Darwin 25.5.0 |
| OS at end | macOS **26.6.1 (25G76)**, Darwin 25.6.0 |
| Python | 3.14.6 (Homebrew), venv at `~/.venvs/mlx` |
| mlx | **0.32.0** |
| mlx-metal | 0.32.0 |
| mlx-lm | **0.31.3** |
| mlx-vlm | **0.6.13** → 0.6.14 |
| transformers | 5.15.0 |
| llama.cpp | build 10472 (commit 7a556b8f9) |
| llama-benchy | 0.4.0 |

Memory bandwidth quoted by the vendor for M5 Max: **614 GB/s** (not
independently verified here).

---

## 2. Models under test

All three derive from the same base: **`Qwen/Qwen3.8-27B`**.

| Build | Repo | Disk | Resident |
|---|---|---|---|
| 4-bit | `mlx-community/Qwen3.8-27B-4bit` | **16.1 GB** | 15.5–15.7 GB |
| 8-bit | `mlx-community/Qwen3.8-27B-8bit` | **28 GB** | 28.1–28.4 GB |
| MTP drafter | `mlx-community/Qwen3.8-27B-MTP-4bit` | **253 MB** | (shared) |

The **same MTP drafter works with both targets**, its own quantisation is
independent of the target's.

### 2.1 Architecture (from `config.json`)

| Field | Value |
|---|---|
| `model_type` | `qwen3_5` |
| `architectures` | `Qwen3_5ForConditionalGeneration` |
| `text_config.model_type` | `qwen3_5_text` |
| `num_hidden_layers` | **64** |
| Layer composition | **48 linear-attention + 16 full-attention** |
| `full_attention_interval` | 4 |
| `hidden_size` | 5120 |
| `vocab_size` | 248320 |
| `max_position_embeddings` | **262144 (256K)** |
| `mtp_num_hidden_layers` | **1** |
| `mtp_use_dedicated_embeddings` | false |
| `pipeline_tag` | `image-text-to-text` (vision-capable) |
| `processor_class` | `Qwen3VLProcessor` |
| `tokenizer_class` | `Qwen2Tokenizer` |
| Quantisation (8-bit) | group_size 64, bits 8, mode affine |

**Naming trap:** `model_type: "qwen3_5"` names the *architecture family*, not
the model version. This IS Qwen3.**8**, `README.md` states
`base_model: Qwen/Qwen3.8-27B`. Qwen2.5 likewise uses `model_type: "qwen2"`.
The same file carries three different generation numbers (`qwen3_5`,
`Qwen3VLProcessor`, `Qwen2Tokenizer`), all naming reused components.

### 2.2 Recommended sampling (from `generation_config.json`)

```json
{ "do_sample": true, "temperature": 1.0, "top_k": 20, "top_p": 0.95 }
```

---

## 3. MTP speculative decoding

### 3.1 The weights are missing from the MLX checkpoint

The config declares an MTP head (`mtp_num_hidden_layers: 1`), but the 8-bit
checkpoint contains **zero MTP tensors**, verified by scanning
`model.safetensors.index.json` for any key matching `nextn|mtp|draft`:
**0 matches**. The MLX conversion (`mlx_vlm.convert`) strips them. They ship
separately as a 253 MB adapter.

### 3.2 `mlx_lm.server` cannot use an MTP drafter

`mlx_lm.server` has `--draft-model` and `--num-draft-tokens`, which makes it
look capable. It has **no `--draft-kind`** and does not support MTP drafters.
`mlx_vlm.server` does, via `--draft-kind {dflash,eagle3,mtp}`.

Confirmation appears in the mlx-vlm server log:

```
Loading speculative drafter (mtp): .../Qwen3.8-27B-MTP-4bit
Drafter ready; speculative decoding enabled.
```

### 3.3 Measured effect, 8-bit, custom harness

3 prompt types, warm model, reasoning OFF, non-streaming, 1 run each.

| Workload | `mlx_lm.server` (no MTP) | `mlx_vlm.server` + MTP | Speedup |
|---|---|---|---|
| Prose, 600 tok | 15.6 t/s | **31.7 t/s** | 2.03x |
| Code, 500 tok | 15.1 t/s | **37.0 t/s** | 2.45x |
| Factual, 400 tok |, | **33.7 t/s** |, |
| **Mean** | **15.5 t/s** | **34.1 t/s** | **2.20x** |

Memory essentially unchanged (~27 GB; drafter adds ~250 MB).

**Speculative decoding is lossless**, the 27B verifies every drafted token, so
the output distribution is identical. This is not a quality/speed trade.

Published comparison for the sibling Qwen3.6-27B on M5 Max via MTPLX:
17 → 48 t/s (2.24x). *(external figure, not measured here)*

### 3.4 4-bit with MTP, same harness

| Workload | 8-bit + MTP | 4-bit + MTP |
|---|---|---|
| Prose | 31.7 t/s | **48.8 t/s** |
| Code | 37.0 t/s | **57.2 t/s** |
| Factual | 33.7 t/s | **54.7 t/s** |
| **Mean** | **34.1 t/s** | **53.6 t/s** |
| vs 15.5 no-MTP baseline | 2.20x | **3.46x** |

---

## 4. Primary benchmark, llama-benchy 0.4.0

Tool: <https://github.com/eugr/llama-benchy>, run via `uvx`. Benchmarks any
OpenAI-compatible endpoint; separates prompt processing (pp) from token
generation (tg); runs a coherence check; reports mean ± stdev.

### 4.1 Exact command

```bash
uvx llama-benchy \
  --base-url http://127.0.0.1:8080/v1 \
  --model ~/models/Qwen3.8-27B-4bit \
  --pp 2048 --tg 128 --depth 0 8192 --runs 3 \
  --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}'
```

### 4.2 Conditions, identical across all cells in §4.3

- **REASONING OFF** (`enable_thinking: false` via `--extra-body`)
- **GPU idle at 2%** before start (all other clients stopped)
- MTP speculative decoding **ON**
- `--max-kv-size 262144 --kv-bits 8`
- Server: `mlx_vlm.server`, `--host 127.0.0.1`, `--max-tokens 4096`
- 3 runs per cell; prompt corpus is a cached Gutenberg text (144,494 tokens)
- Measured API latency overhead: **2.85 ms**
- Coherence test: **PASSED**

### 4.3 Results, reasoning OFF, clean GPU

| Metric | 4-bit | 8-bit |
|---|---|---|
| Prompt processing @ depth 0 | **765.45 ± 19.11 t/s** | 608.55 ± 11.13 t/s |
| **Token generation @ depth 0** | **47.53 ± 4.81 t/s** | **30.17 ± 0.69 t/s** |
| Peak tg @ depth 0 | 48.00 ± 4.97 | 30.67 ± 0.94 |
| TTFR / e2e TTFT @ depth 0 | 2681.11 ± 67.42 ms | 3370.79 ± 62.07 ms |
| Prompt processing @ depth 8192 | 713.78 ± 13.64 t/s | 686.30 ± 8.41 t/s |
| **Token generation @ depth 8192** | **35.06 ± 2.18 t/s** | **24.12 ± 1.60 t/s** |
| Peak tg @ depth 8192 | 35.67 ± 2.05 | 24.67 ± 1.89 |
| TTFR / e2e TTFT @ depth 8192 | 14355.43 ± 277.12 ms | 14926.77 ± 180.68 ms |

**4-bit generates 1.57x faster than 8-bit** (47.53 / 30.17).

### 4.4 Context depth costs ~a quarter of decode speed

| Build | tg @ d0 | tg @ d8192 | Loss |
|---|---|---|---|
| 4-bit | 47.53 t/s | 35.06 t/s | **−26.2%** |
| 8-bit | 30.17 t/s | 24.12 t/s | **−20.1%** |

TTFT rises to ~14–15 s at 8K depth on **both** builds. Headline t/s figures are
depth-0 numbers and do not survive a filled context.

Note the 8-bit's prompt processing *rises* with depth (608.6 → 686.3 t/s) while
the 4-bit's falls (765.5 → 713.8). Both cross near ~700 t/s at depth.

### 4.5 Contended vs clean, how much other load costs

The same 4-bit suite run while 5 Qwen Code sessions held the GPU at 98%:

| Metric | Contended (98% GPU) | Clean (2% GPU) | Delta |
|---|---|---|---|
| pp2048 @ d0 | 851.89 ± 68.56 t/s | 765.45 ± 19.11 t/s | +11% * |
| **tg128 @ d0** | 45.23 ± 0.21 t/s | **47.53 ± 4.81 t/s** | **−4.8%** |
| tg128 @ d8192 | 33.91 ± 1.56 t/s | 35.06 ± 2.18 t/s | −3.3% |
| ttfr @ d0 | 2423.77 ± 194.85 ms | 2681.11 ± 67.42 ms |, |

\* The contended pp figure is higher but with 3.6x the stdev; treat as noise
rather than a real gain. Generation degraded ~3–5% under heavy contention n/a
less than expected, and stdev is much tighter on the clean runs.

---

## 5. Reasoning on vs off

### 5.1 Throughput is unaffected

8-bit, depth 0, pp2048 / tg128, 2 runs, `reasoning_effort: low`:

| Condition | Token generation | Prompt processing | TTFR |
|---|---|---|---|
| Reasoning **OFF** | **30.17 ± 0.69 t/s** | 608.55 ± 11.13 t/s | 3370.79 ± 62.07 ms |
| Reasoning **ON** (low) | **30.26 ± 0.47 t/s** | 716.63 ± 1.60 t/s | 2861.67 ± 6.39 ms |

**Identical within noise** (30.26 vs 30.17 t/s). Reasoning does not slow token
generation.

### 5.2 The cost is tokens, not throughput

Reasoning tokens are generated **before any visible output** and are **not
counted in `completion_tokens`**. The same question, same visible answer:

| `reasoning_effort` | Wall time | Visible tokens | Answer |
|---|---|---|---|
| `low` | **5.3 s** | 2 | "Wednesday" |
| `xhigh` | **62.0 s** | 2 | "Wednesday" |

**11.7x the wall time for identical output**, invisible in the token counts.

### 5.3 `xhigh` can return nothing at all

With `enable_thinking: true` and no explicit effort, the chat template defaults
to **`xhigh`**. Measured: **193.6 s, hit a 3000-token cap, `content` empty** n/a
the model was still reasoning when it ran out of budget. The same call at
`low` effort returned a complete answer.

Effort levels accepted: **`low`, `medium`, `xhigh`** (default `xhigh`).
Anything else raises an exception from the template.

### 5.4 More reasoning is not more accuracy

The `low` and `xhigh` runs in §5.2 both answered "Wednesday". Monday + 45 days
is **Thursday** (45 mod 7 = 3). 62 seconds of extra reasoning did not fix a
wrong answer.

---

## 6. Quality spot checks

**These are far too small to establish quality equivalence.** Reported for
completeness only.

Set A, 5 questions, reasoning off, both builds:

| Question | Expected | 4-bit | 8-bit |
|---|---|---|---|
| 17 × 23 | 391 | ✅ | ✅ |
| Smallest taxicab number | 1729 | ✅ | ✅ |
| Bat and ball | $0.05 | ✅ | ✅ |
| Primes 1–30 | 10 | ✅ | ✅ |
| listen/silent anagram | yes | ✅ | ✅ |
| **Score** | | **5/5** | **5/5** |

Set B, earlier 5-question set: both scored **4/5**, both missing the same
day-of-week question with the same wrong answer.

Code output differed in style but both were correct:
- 4-bit: `sorted(set(lst), reverse=True)[1]`
- 8-bit: `max(set(lst) - {max(lst)})`

---

## 7. Sampling behaviour, a silent-failure trap

### 7.1 `mlx_lm.server` defaults to greedy

`mlx_lm.server` ignores the model's `generation_config.json` and defaults to
**temperature 0.0**, greedy decoding, on a model that asks for temp 1.0 /
top-k 20 / top-p 0.95. No warning is emitted. Explicit flags are required.

### 7.2 `mlx_vlm.server` reads the model config

`mlx_vlm.server` resolves defaults from the model's own config
(`request_normalization.py` → `_model_config_field_or_default`). Verified
empirically on the same prompt:

| Request | Output identical to… |
|---|---|
| No sampling params | **model config (temp 1.0 / top-k 20 / top-p 0.95)** |
| `temperature: 0.0` | different, so the default is **not** greedy |
| `temperature: 1.0, top_k: 20, top_p: 0.95` | matches the default exactly |

### 7.3 Output is deterministic

The server uses a fixed RNG seed. Three identical requests return
byte-identical output at any temperature. Temperature still works, 2.0 and 5.0
produce progressively degraded text, but identical requests never vary.

---

## 8. GPU memory behaviour

Apple Silicon has no discrete VRAM. Figures are GPU-allocated unified memory,
read from the IOAccelerator driver:

```bash
ioreg -r -c IOAccelerator -d 1   # "Alloc system memory", "In use system memory"
```

### 8.1 Allocation ratchets upward with use

Single 4-bit model (15.7 GB resident) over one session:

| State | GPU allocated | GPU in use |
|---|---|---|
| No model loaded | 1.91–2.15 GB | 0.87–1.13 GB |
| Model loaded, idle | **17.44 GB** | 1.17 GB |
| **During inference** | **45.04 GB** | 44.19 GB |
| After request settles | **30.88 GB** | 1.03 GB |
| After a long agent session | **105.30 GB** | 104.15 GB |

Allocation nearly **tripled during generation** on a 15.7 GB model, KV cache
and activation buffers at 256K context, and did **not** return to baseline
between requests. Over one long agent session it climbed **17 → 105 GB**, with
system free memory falling from 96% to 13%.

---

## 9. Kernel panics, an Apple GPU driver bug

### 9.1 Three identical panics in three days

```
panic(cpu N caller ...): "completeMemory() prepare count underflow"
  @IOGPUMemory.cpp:550
kext: com.apple.iokit.IOGPUFamily(130.15.2)
```

| Date | Panicking task | Memory held at panic |
|---|---|---|
| 2026-08-15 19:23 | Python (MLX) | **30.0 GB** |
| 2026-08-16 11:49 | Python (MLX) | **4.5 GB** |
| 2026-08-17 09:48 | Python (MLX) | **16.6 GB** |

The panicking task was **always the MLX Python process**. Never llama.cpp.

**The 4.5 GB case rules out memory pressure as the cause**, that is 3.5% of
128 GB. It is a reference-count underflow in Apple's GPU driver (a premature
release / double-free of a GPU memory object), which MLX's allocation pattern
triggers reliably.

The 2026-08-15 panic followed 20.7 days of uptime and a 7-minute sleep/wake
cycle 7 hours earlier.

### 9.2 Known upstream, not specific to this machine

- [ml-explore/mlx#3346](https://github.com/ml-explore/mlx/issues/3346), same panic, macOS 26.4, M3 Ultra
- [ml-explore/mlx#3186](https://github.com/ml-explore/mlx/issues/3186), M4 Max, large context prefill (~173K tokens)
- [ml-explore/mlx-lm#883](https://github.com/ml-explore/mlx-lm/issues/883), `mlx_lm.server`, unbounded memory growth; panicked at 80 GB of 96 GB
- [exo-explore/exo#1972](https://github.com/exo-explore/exo/issues/1972), M4 Max 128 GB
- jundot/omlx #557, #1384, #300

mlx-lm#883 reports three contributing factors: the server wires ~75% of RAM at
startup, the KV cache grows unbounded, and there are no memory safeguards.
[PR #906](https://github.com/ml-explore/mlx-lm/pull/906) (merged 2026-02-19)
added `--prompt-cache-bytes` to bound saved caches by bytes.

**That fix is in `mlx_lm.server` only.** `mlx_vlm.server`, the one that
supports MTP, has no `--prompt-cache-bytes`. Its `PromptCacheState` holds a
single unbounded cache. It does have `--max-kv-size` and `--kv-bits`.

Reported mitigation in llama.cpp/Ollama: a **fixed context size at startup**
keeps the KV cache bounded, preventing the growth that precedes the panic.

### 9.3 After the OS update

Upgrading **26.5.2 → 26.6.1** produced **zero panics in 8+ hours** of heavy use,
versus roughly one per day before. Too short a window to call it fixed.

### 9.4 `--max-kv-size` is not the memory guard it appears to be

The server budgets `prompt + max_generation` against `MAX_KV_SIZE`, not just
the prompt:

```
Request needs 137255 context tokens (73255 prompt + 64000 max generation),
but MAX_KV_SIZE is 131072.
```

Because clients reserve generation budget up front (Qwen Code reserves 64,000
tokens per request), the cap **cannot be set below what the client reserves**
without rejecting valid work with HTTP 400. It ended up raised to the model's
own 262144 ceiling, i.e. no effective bound.

**`--kv-bits 8` is the real memory saver** (halves the KV cache regardless of
length). Capping client-side `max_tokens` (64000 → 16384) frees far more
budget than tightening `--max-kv-size`.

---

## 10. Cross-check: llama.cpp with an Unsloth Dynamic quant

### 10.1 Setup

| | |
|---|---|
| Model | `unsloth/Qwen3.8-27B-GGUF` → `Qwen3.8-27B-UD-Q4_K_XL.gguf` |
| Size | **17 GB** (17.9 GB reported by HF) |
| Quantisation | **Unsloth Dynamic V3.0** (selective per-layer precision) |
| Runtime | llama.cpp build 10360, Metal, `-ngl -1 -c 8192 -fa auto` |
| Resident | **17.7 GB** |

### 10.2 Results, same harness, same prompts as §3.4

| Workload | MLX 4-bit | llama.cpp UD-Q4_K_XL |
|---|---|---|
| Prose, 500 tok | 43.4 t/s | 24.9 t/s |
| Code, 500 tok | 53.6 t/s | 24.7 t/s |
| Factual, 400 tok | 50.7 t/s | 24.1 t/s |
| **Mean** | **49.2 t/s** | **24.6 t/s** |
| Quality (Set A) | 5/5 | 5/5 |
| Resident | 15.5 GB | 17.7 GB |

**MLX is 2.0x faster at the same nominal bit-width**, using less memory.

### 10.3 llama.cpp discarded the MTP weights

The GGUF **contains** MTP tensors, but this llama.cpp build ignores them:

```
W model has unused tensor blk.64.nextn.eh_proj.weight (size = 43008000 bytes) -- ignoring
W model has unused tensor blk.64.nextn.enorm.weight -- ignoring
W model has unused tensor blk.64.nextn.hnorm.weight -- ignoring
W model has unused tensor blk.64.nextn.shared_head_norm.weight -- ignoring
```

So the comparison is **MLX-with-MTP vs llama.cpp-without-MTP**, even though the
drafter was present in the file. Part of the 2.0x gap is that asymmetry, not
raw runtime speed.

### 10.4 Quantisation formats are not interchangeable

| Format | Runtime | Dynamic quant? |
|---|---|---|
| MLX 4-bit / 8-bit (mlx-community) | MLX | ❌ uniform |
| GGUF UD-*_XL (Unsloth) | llama.cpp | ✅ Dynamic V3.0 |
| NVFP4 (Unsloth) | vLLM / CUDA | ✅ Dynamic V3.0 |

**Unsloth publishes no MLX build of Qwen3.8** (base, FP8, GGUF, NVFP4 only), so
Dynamic quantisation and MLX speed cannot currently be combined on this model.
Unsloth does ship `unsloth/Qwen3.6-27B-UD-MLX-6bit`, so the format exists in
their catalogue for the previous generation.

MLX 6-bit builds of Qwen3.8 exist from other publishers (lmstudio-community,
lukaskremla, TheCluster and ~17 others, ~22.8 GB) but are uniform quants.
`mlx-community/Qwen3.8-27B-6bit` specifically does **not** exist (404).

### 10.5 What Unsloth Dynamic actually does

From `unsloth/Qwen3.8-27B-NVFP4`'s `config.json`, mixed precision by layer group:

| Precision | Applied to |
|---|---|
| **8-bit FP8** | all attention projections (q/k/v/o), linear-attention in/out projections, `lm_head`, and MLP of the **last 8 layers (56–63)** |
| **4-bit NVFP4** | all other MLP gate/up/down projections (the bulk of parameters) |
| **Unquantised** | entire vision tower (27 blocks), linear-attention internals across ~48 layers, and **all MTP weights** (`re:^mtp.*`) |

Leaving the MTP weights unquantised is deliberate: drafter accuracy drives the
speculative acceptance rate.

---

## 11. Reproduction

### 11.1 Serve with MTP

```bash
python -m pip install -U mlx-vlm            # 0.6.14

python -c "
from huggingface_hub import snapshot_download
snapshot_download('mlx-community/Qwen3.8-27B-MTP-4bit',
                  local_dir='~/models/Qwen3.8-27B-MTP-4bit')"

mlx_vlm.server \
  --model       ~/models/Qwen3.8-27B-4bit \
  --draft-model ~/models/Qwen3.8-27B-MTP-4bit \
  --draft-kind  mtp \
  --host 127.0.0.1 --port 8080 \
  --max-kv-size 262144 --kv-bits 8 \
  --max-tokens 4096
```

`--host 127.0.0.1` is required: **`mlx_vlm.server` defaults to `0.0.0.0`**,
exposing the model to the whole network.

### 11.2 Benchmark

```bash
uvx llama-benchy --base-url http://127.0.0.1:8080/v1 \
  --model /path/to/Qwen3.8-27B-4bit \
  --pp 2048 --tg 128 --depth 0 8192 --runs 3 \
  --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}'
```

Omitting `--extra-body` benchmarks **with reasoning on**, the template
defaults to `enable_thinking: true` at `xhigh` effort.

### 11.3 Watch GPU memory

```bash
ioreg -r -c IOAccelerator -d 1 | grep -o '"Alloc system memory"=[0-9]*'
```

---

## 12. Summary of findings

1. **MTP speculative decoding gives 2.20x** on 8-bit (15.5 → 34.1 t/s),
   losslessly. The weights are stripped from MLX checkpoints and must be
   fetched separately (253 MB).
2. **`mlx_lm.server` cannot use MTP drafters**; `mlx_vlm.server` can. The fix
   is a server swap, not a flag.
3. **4-bit generates 1.57x faster than 8-bit** (47.53 vs 30.17 t/s at depth 0),
   using 15.5 GB vs 28.1 GB.
4. **Context depth costs 20–26% of decode speed** by 8K tokens, and pushes TTFT
   to ~15 s on both builds.
5. **Reasoning does not slow generation** (30.26 vs 30.17 t/s), it adds
   uncounted tokens. `xhigh` took 11.7x the wall time of `low` for identical
   output, and can exhaust a token budget producing nothing.
6. **`mlx_lm.server` silently defaults to greedy decoding**;
   `mlx_vlm.server` reads the model's own sampling config.
7. **GPU allocation ratchets upward**, 17 → 105 GB over one session, and
   precedes a known Apple driver kernel panic
   (`IOGPUMemory.cpp:550`) that fired 3 times in 3 days, including once at
   only 4.5 GB held.
8. **MLX is 2.0x faster than llama.cpp** at the same nominal bit-width, though
   llama.cpp silently discarded the MTP weights present in the GGUF.
9. **Unsloth Dynamic quantisation is unavailable for Qwen3.8 on MLX**, so
   dynamic-quant quality and MLX speed cannot currently be combined.
