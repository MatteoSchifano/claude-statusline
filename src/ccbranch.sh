#!/bin/bash
#
# ccbranch.sh - rename the current git branch from the terminal.
#
# The Claude Code statusline is display-only (it cannot accept keystrokes), so
# branch editing lives here as a tiny companion command. Pair it with the
# statusline's line-1 branch display.
#
# Usage:
#   ccbranch <new-name>     Rename the current branch to <new-name>
#   ccbranch -h | --help    Show this help
#
# Suggested alias (add to ~/.zshrc or ~/.bashrc):
#   alias ccbranch="$HOME/Documents/Projects/cc-statusline/src/ccbranch.sh"
#
# Author: cc-statusline
# License: MIT

set -euo pipefail

usage() {
    cat <<'EOF'
ccbranch - rename the current git branch

Usage:
  ccbranch <new-name>     Rename the current branch to <new-name>
  ccbranch -h | --help    Show this help

Notes:
  - Run from inside the repository whose branch you want to rename.
  - This only renames locally (git branch -m). Push with:
      git push origin -u <new-name>
    and, if needed, delete the old upstream branch on the remote.
EOF
}

main() {
    if [ "$#" -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        [ "$#" -eq 0 ] && return 1 || return 0
    fi

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ccbranch: not inside a git repository." >&2
        return 1
    fi

    local new_name="$1"
    local current
    current=$(git branch --show-current 2>/dev/null)

    if [ -z "$current" ]; then
        echo "ccbranch: detached HEAD — check out a branch before renaming." >&2
        return 1
    fi

    if [ "$current" = "$new_name" ]; then
        echo "ccbranch: already on '$new_name', nothing to do."
        return 0
    fi

    git branch -m "$new_name"
    echo "ccbranch: renamed '$current' -> '$new_name'"

    # Hint about the upstream if the old branch was tracked
    if git config "branch.${new_name}.merge" >/dev/null 2>&1; then
        echo "ccbranch: tip — update the remote with: git push origin -u '$new_name'"
    fi
}

main "$@"
