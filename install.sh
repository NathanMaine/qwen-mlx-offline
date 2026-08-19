#!/usr/bin/env bash
# Set up the MLX runtime and put the qwen-* commands on your PATH.
# Downloads no models; it tells you which to fetch and how.
set -euo pipefail

VENV="${QWEN_VENV:-$HOME/.venvs/mlx}"
BIN="${QWEN_BIN_DIR:-$HOME/.local/bin}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\033[36m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only (this uses Apple Metal via MLX)"
[ "$(uname -m)" = "arm64" ] || die "Apple Silicon required; got $(uname -m)"

RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
say "Detected $(sysctl -n machdep.cpu.brand_string), ${RAM_GB} GB unified memory"
if [ "$RAM_GB" -lt 32 ]; then
  die "need at least 32 GB for the 4-bit model (you have ${RAM_GB} GB)"
elif [ "$RAM_GB" -lt 64 ]; then
  say "note: ${RAM_GB} GB fits the 4-bit model; the 8-bit needs 64 GB+"
fi

command -v python3 >/dev/null || die "python3 not found"

say "Creating venv at $VENV"
python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install -q -U pip
say "Installing mlx-vlm (this pulls mlx and mlx-lm)"
"$VENV/bin/python" -m pip install -q -U mlx-vlm huggingface_hub

say "Linking commands into $BIN"
mkdir -p "$BIN"
for f in "$HERE"/bin/*; do
  ln -sf "$f" "$BIN/$(basename "$f")"
done
# mlx_vlm.server and friends need to be reachable too
for f in "$VENV"/bin/mlx_vlm* "$VENV"/bin/mlx_lm*; do
  [ -e "$f" ] && ln -sf "$f" "$BIN/$(basename "$f")"
done

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "WARNING: $BIN is not on your PATH. Add this to ~/.zshrc:"
     printf '\n    export PATH="%s:$PATH"\n\n' "$BIN" ;;
esac

cat <<EOF

$(printf '\033[32mInstalled.\033[0m') Now fetch the models you want:

  # 4-bit, 16 GB, the everyday one
  hf download mlx-community/Qwen3.8-27B-4bit \\
    --revision 3e6447f082e89cc7f0bc6e5441afd38dfce760ff \\
    --local-dir ~/models/Qwen3.8-27B-4bit

  # MTP drafter, 253 MB, doubles decode speed, works with BOTH quants
  hf download mlx-community/Qwen3.8-27B-MTP-4bit \\
    --revision b643c01b6d3b094e325edb6ebd832e16c486c575 \\
    --local-dir ~/models/Qwen3.8-27B-MTP-4bit

  # --revision pins the exact weights these benchmarks used. mlx-community
  # re-quantizes in place, so the repo id alone is not a version. See VERSIONS.md.
EOF

if [ "$RAM_GB" -ge 64 ]; then
cat <<EOF
  # 8-bit, 28 GB, optional
  hf download mlx-community/Qwen3.8-27B-8bit \\
    --revision 815b83c0df8ffd1d1b5244cf75fd6ef14fca9ef9 \\
    --local-dir ~/models/Qwen3.8-27B-8bit
EOF
fi

cat <<EOF

Then:

  qwen-preflight 4        # machine, OS, Rosetta, weights, versions
  qwen-serve start 4
  qq "hello"
  qwen-offline-check 4    # turn off the Wi-Fi first, that is the point

Optional, for double-click launchers:

  cp "$HERE"/launchers/*.command ~/Applications/

EOF
