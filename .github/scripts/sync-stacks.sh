#!/usr/bin/env bash
# Prints the stacks (directories with a sync.yml) to sync, one per line.
#
#   EVENT  - github.event_name
#   BEFORE - github.event.before (push)
#   AFTER  - commit being synced (push)
#   STACK  - stack picked on workflow_dispatch; empty means all
#
# A push syncs the stacks whose directory changed; changes to common/ or to the sync workflow sync all of them.
set -euo pipefail

all=$(for config in */sync.yml; do dirname "$config"; done | sort)

case "${EVENT}" in
  push)
    if [ -z "${BEFORE:-}" ] || ! git cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
      echo "${all}"
      exit 0
    fi
    changed=$(git diff --name-only "${BEFORE}" "${AFTER}")
    if grep -qE '^(common/|\.github/workflows/sync\.yml$|\.github/scripts/sync-stacks\.sh$)' <<< "${changed}"; then
      echo "${all}"
    else
      cut -d/ -f1 <<< "${changed}" | sort -u | grep -Fx -f <(echo "${all}") || true
    fi
    ;;
  workflow_dispatch)
    if [ -z "${STACK:-}" ]; then
      echo "${all}"
    elif grep -Fxq "${STACK}" <<< "${all}"; then
      echo "${STACK}"
    else
      echo "There is no ${STACK}/sync.yml; stacks: $(tr '\n' ' ' <<< "${all}")" >&2
      exit 1
    fi
    ;;
  *)
    echo "${all}"
    ;;
esac
