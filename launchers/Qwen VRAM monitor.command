#!/bin/bash
# Double-click launcher — live view of what is using GPU memory.
cd "$HOME"
exec "$HOME/.local/bin/vram" --watch
