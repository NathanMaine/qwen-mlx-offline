# The shortcuts

Running a local model well is mostly a question of friction. A 27B model that
takes three commands and a remembered flag to start is a model you stop
reaching for. These exist so the answer to "should I just ask the local one?"
is always yes.

Seven commands, each doing one thing. Every one also has a double-clickable
`.command` launcher in `launchers/` for when you are not already in a terminal.

---

## `qq` - ask it something

The one you will use most.

```bash
qq "what does ENOTTY mean"
qq "review this" < diff.txt
git diff | qq "write a commit message"
cat error.log | qq "what is failing here"
qq -i                                    # stay in a conversation
```

It reads stdin, so it composes with everything else you already do in a shell.
Output streams as it generates, so you start reading before it finishes.

| Flag | Effect |
|---|---|
| `-i` | Interactive multi-turn |
| `--think` | Reasoning on. Goes to **stderr**, so pipes stay clean |
| `--effort low\|medium\|xhigh` | How hard to think, default `low` |
| `-m N` | Max tokens |
| `-s TEXT` | System prompt |

Two deliberate choices. **Reasoning is off by default**, the inverse of the
model's own default, because for a one-line question the thinking costs more
time than the answer. And when you do use `--think`, the reasoning goes to
stderr rather than stdout, so `git diff | qq --think "review" > out.md` gives
you a clean file and the thinking on screen.

It also **starts the server for you** if it is not running. A cold first call
takes about ten seconds; after that it is instant.

---

## `qwen-local-4` and `qwen-local-8` - agentic coding

These launch Qwen Code, the full agent that reads and edits files, against your
local model.

```bash
cd ~/some-project
qwen-local-4        # 4-bit,  ~48 tok/s
qwen-local-8        # 8-bit,  ~30 tok/s
```

Each prints a green banner naming the quant before handing over, so you always
know which one you are talking to. Extra arguments pass straight through:
`qwen-local-4 -p "review this repo"` runs non-interactively.

**Which one:** 4-bit for anything iterative, where waiting is the cost. 8-bit
when you would rather it got the answer right the first time. The server
hot-swaps between them in about two seconds, so the choice is not a commitment.

---

## `qwen-serve` - the engine

Everything else talks to this. You rarely call it directly.

```bash
qwen-serve start 4       # load the 4-bit
qwen-serve start 8       # swap to the 8-bit
qwen-serve status        # what is loaded, with real memory
qwen-serve stop
qwen-serve log           # tail the server log
```

`status` reports what is **actually loaded** rather than what the defaults say
it should be, which matters once you have swapped quants a few times. It also
prints real resident memory rather than a guess.

The interesting part is `start`: if a different quant is already running, it
swaps rather than silently ignoring you. That bug cost me a corrupted benchmark
before it got fixed.

---

## `qwen-stop` - give the memory back

```bash
qwen-stop
# qwen: unloaded, 15.7 GB freed
```

More careful than it looks. `mlx_vlm.server` **releases its listening socket
while still holding the model**, so anything that checks only the port will
tell you it unloaded while 28 GB is still resident. `qwen-stop` waits for the
process itself to exit, escalates to SIGKILL if it has to, and exits non-zero
naming any survivor.

Worth running before you close the lid or reboot. Memory teardown is where the
GPU driver is least happy, and going into a restart holding 28 GB of buffers is
the riskiest moment. See [STABILITY.md](STABILITY.md).

---

## `qwen-think` - the reasoning toggle

```bash
qwen-think off        # fast, no thinking
qwen-think on         # thinking at low effort
qwen-think low|medium|xhigh
qwen-think status
```

This flips reasoning for the Qwen Code providers, both quants at once. Restart
Qwen Code afterwards, since it reads its config at startup.

Why a toggle rather than a setting you forget: reasoning does **not** slow
token generation at all (30.26 vs 30.17 tok/s, identical within noise). What it
does is add tokens you never see, generated before any visible output and often
not counted in the usage stats. The same two-token answer took **5.3 seconds at
`low` and 62.0 seconds at `xhigh`**, and both were wrong in the same way.

For mechanical work, turn it off. For a genuinely hard problem, `low` is
usually enough, and `xhigh` has a habit of exhausting its token budget while
still thinking, returning nothing at all.

---

## `vram` - what is actually using the GPU

```bash
vram          # snapshot
vram -w       # live, refreshes every 2s
```

```
GPU (unified memory, no separate VRAM on Apple Silicon)
  allocated to GPU :  17.44 GB
  in use by GPU    :   1.17 GB
  device util      :   8 %
  system memory    : 128 GB total, 96% free

Processes holding model weights
      PID   RESIDENT    PORT       UPTIME  RUNTIME / MODEL
     2823   15.71 GB    8080        00:04  MLX (mlx-vlm) / Qwen3.8-27B-4bit
```

The GPU numbers come from the IOAccelerator driver via `ioreg`, so they are
real allocations rather than estimates. It also finds MLX, llama.cpp, Ollama,
vLLM, LM Studio and Unsloth Studio, which is how you discover the model server
you forgot to stop three hours ago.

Leave `vram -w` running as long as you like. Measured over 30 refreshes it grew
by 96 KB and allocated no GPU memory of its own.

The reason to care: allocation **ratchets upward** during long sessions rather
than returning to baseline. On one run it climbed from 17 GB to 105 GB. This is
the tool that tells you before it becomes a problem.

---

## `qwen-bench` - is it still fast

```bash
qwen-bench
```

Times short, medium and long prompts and reports time-to-first-token plus
decode rate for each. It refuses to pretend, warning you if the GPU is already
busy, because benchmarking against a loaded machine measures contention rather
than your setup.

Useful after changing anything, or when the model feels slower than you
remember.

---

## How they fit together

A normal day never involves `qwen-serve` at all:

```bash
qq "quick question"              # server starts itself
cd ~/project && qwen-local-4     # agent work, same server
qwen-stop                        # done for the day
```

The design rule throughout: **each command does one thing, tells you what it
did, and verifies it happened.** `qwen-stop` confirms the memory came back.
`qwen-serve status` reports reality rather than defaults. `qwen-bench` refuses
to report a number it does not trust. Every one of those checks exists because
its absence cost me something first.
