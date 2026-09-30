#!/usr/bin/env bash
# Prints the ref to diff a branch against: origin/main if it resolves, else a local main, else the root commit.
# Used by the reviewer so it never PASSes on an empty diff when there is no remote.
for ref in origin/main origin/master main master; do
  if git rev-parse --verify -q "$ref" >/dev/null 2>&1; then echo "$ref"; exit 0; fi
done
git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1
