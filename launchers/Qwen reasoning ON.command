#!/bin/bash
# Double-click — set reasoning on for the local Qwen models in Qwen Code.
cd "$HOME"
"$HOME/.local/bin/qwen-think" on
echo
echo "Restart Qwen Code for this to take effect."
echo "Press any key to close..."
read -n 1
