#!/usr/bin/env bash
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

echo "🦙 Ollama Model Downloader"
echo "=========================="
echo ""

download_model() {
    local model=$1
    echo "Downloading: ${model}..."
    if curl -X POST "${OLLAMA_HOST}/api/pull" -d "{\"name\":\"${model}\"}" 2>/dev/null; then
        echo "✅ ${model} downloaded successfully"
    else
        echo "❌ Failed to download ${model}"
    fi
    echo ""
}

download_model "llama3.2:latest"
echo "✅ Model download complete!"
