#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

blocked=0

tracked_runtime="$(git ls-files 2>/dev/null | grep -E '(^|/)(claude_token[^/]*|status\.json|usage-[^/]*\.jsonl)$' || true)"
if [[ -n "$tracked_runtime" ]]; then
    echo "Blocked runtime files are tracked:"
    echo "$tracked_runtime"
    blocked=1
fi

secret_hits="$(git grep -Il -E '(sk-ant-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{30,})' -- . 2>/dev/null || true)"
if [[ -n "$secret_hits" ]]; then
    echo "Possible credentials found in:"
    echo "$secret_hits"
    blocked=1
fi

if (( blocked )); then
    exit 1
fi

echo "Public-source safety check passed."
