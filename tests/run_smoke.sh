#!/usr/bin/env bash
# Сокращение для удобства: ./tests/run_smoke.sh
exec "$(dirname "$0")/../tools/headless/run_smoke.sh" "$@"
