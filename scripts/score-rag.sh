#!/usr/bin/env bash
# Run RAG self-score tests and print summary.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
echo "== Knowledge RAG self-score =="
swift test --filter 'RetrievalEvalTests|RAGTests' 2>&1 | tee /tmp/knowledge-rag-score.log
echo ""
echo "---- score lines ----"
grep -E 'SCORE |Test Case|passed|failed|error:' /tmp/knowledge-rag-score.log | tail -40
echo ""
echo "See docs/rag_scorecard.md for area weights."
echo "After code change: re-sync corpus in app so meeting labels/chunks refresh."
