# Stability on long runs

Running a 27B model for hours is where the interesting failure modes live.
This is what happened over four days of heavy use, and what to do about it.

## GPU memory ratchets upward

Apple Silicon has no discrete VRAM, so "GPU memory" is the GPU's slice of
unified memory. Read it with:

```bash
vram          # or: vram -w  for a live view
```

Measured on a single 4-bit model (15.7 GB resident) over one session:

| State | GPU allocated |
|---|---|
| No model loaded | 1.9 GB |
| Model loaded, idle | 17.4 GB |
| **During inference** | **45.0 GB** |
| After the request settles | 30.9 GB |
| After a long agent session | **105.3 GB** |

Allocation nearly tripled during generation on a 15.7 GB model, which is KV
cache and activation buffers at 256K context. It does **not** return to
baseline between requests. Over one long agent session it climbed from 17 GB
to 105 GB, with free system memory falling from 96% to 13%.

**This is the thing to watch.** `vram -w` in a spare terminal costs nothing
and tells you immediately.

## Kernel panics: an Apple driver bug

Three panics in three days, all identical:

```
panic(cpu N caller ...): "completeMemory() prepare count underflow"
  @IOGPUMemory.cpp:550
kext: com.apple.iokit.IOGPUFamily
```

The panicking task was **always** the MLX Python process, never llama.cpp.
Memory held at panic: 30.0 GB, **4.5 GB**, 16.6 GB.

The 4.5 GB case matters, because it rules out memory pressure as the cause.
That is 3.5% of 128 GB. This is a reference-count underflow in Apple's GPU
driver that MLX's allocation pattern triggers reliably.

It is known upstream and not specific to any one machine:

- [ml-explore/mlx#3346](https://github.com/ml-explore/mlx/issues/3346), M3 Ultra
- [ml-explore/mlx#3186](https://github.com/ml-explore/mlx/issues/3186), M4 Max, large context prefill
- [ml-explore/mlx-lm#883](https://github.com/ml-explore/mlx-lm/issues/883), unbounded growth, panicked at 80 GB of 96 GB
- [exo-explore/exo#1972](https://github.com/exo-explore/exo/issues/1972), M4 Max 128 GB

### What helps

**Update macOS.** Going from 26.5.2 to 26.6.1 took it from roughly one panic
per day to zero in 8+ hours of heavy use. That is a short window and not proof,
but it is the only fix that changes kernel driver code.

**Unload before sleeping or rebooting.** The failing path is memory *teardown*,
so going into a restart holding 28 GB of GPU buffers is the riskiest moment.
`qwen-stop` frees it and verifies the process actually exited.

**Do not swap quants constantly.** Each `qwen-serve start 4|8` swap frees
16-28 GB of GPU buffers through exactly the failing path. Pick one and stay on
it for long runs.

**`--kv-bits 8` is the real memory saver**, not `--max-kv-size`. It halves the
KV cache regardless of conversation length. Both are set by default in
`qwen-serve`.

### What does not help

**`--max-kv-size` cannot be tightened much.** The server budgets
`prompt + max_generation` against it, not just the prompt:

```
Request needs 137255 context tokens (73255 prompt + 64000 max generation),
but MAX_KV_SIZE is 131072.
```

Clients reserve generation budget up front (Qwen Code asks for 64,000 tokens
per request), so the cap cannot go below what the client reserves without
rejecting valid work with HTTP 400. Capping the client's `max_tokens` frees far
more budget than tightening the server cap.

**Switching harness does not help.** Anything built on MLX hits the same
driver bug. llama.cpp avoids it by fixing context size at startup so the KV
cache stays bounded, but on this hardware llama.cpp measured half the speed
(24.6 vs 49.2 t/s).

## `qwen-stop` verifies, and you should care

`mlx_vlm.server` drops its listening socket while still holding the model. A
port check alone will report "unloaded" with 28 GB still resident. `qwen-stop`
waits for the **process** to exit, escalates to SIGKILL, and exits non-zero
naming any survivor.
