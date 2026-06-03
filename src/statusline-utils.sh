#!/usr/bin/env bash
# statusline-utils.sh - Utility functions for official Anthropic weekly reset tracking
# This file provides ccusage_r scheme support for matching official console reset schedule

# Constants
readonly WEEK_DURATION_SECONDS=604800  # 7 days
readonly DAY_DURATION_SECONDS=86400    # 24 hours

# ====================================================================================
# CCUSAGE EXECUTION & CACHING
# ====================================================================================
# These helpers eliminate the two dominant latency costs of the statusline:
#   1. `npx --yes ccusage@X` re-resolves the package on every invocation (~1.7s of
#      pure overhead). We prefer a globally-installed `ccusage` binary when present.
#   2. Several sections independently shell out to an *identical* `ccusage blocks
#      --json` (~3.4s each). We cache the raw JSON to disk with a TTL so that, within
#      a single render AND across renders inside the TTL window, each distinct ccusage
#      command runs at most once.
# Together these turn a multi-second, multi-call render into (at most) one ccusage
# call per distinct command, served from cache the rest of the time.

# Resolve the ccusage invocation. Prefers the global binary (no npx package
# resolution); falls back to the version-pinned npx form when no global install
# exists. Honors CCUSAGE_VERSION when set by the caller (defaults to 17.1.0).
resolve_ccusage_cmd() {
    if command -v ccusage >/dev/null 2>&1; then
        echo "ccusage"
    else
        echo "npx --yes ccusage@${CCUSAGE_VERSION:-17.1.0}"
    fi
}

# Directory for raw ccusage output caches (separate from the derived daily/weekly
# caches managed by statusline-cache.sh).
_ccusage_cache_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir/../data"
}

# File mtime in epoch seconds, portable across macOS (BSD) and Linux (GNU) stat.
_file_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# Run a ccusage subcommand with TTL-based file caching of its raw JSON output.
# Usage: ccusage_cached <cache_name> <ttl_seconds> <ccusage args...>
# `--offline` is appended automatically. Returns cached JSON on a fresh hit;
# otherwise runs ccusage, refreshes the cache atomically (tmp -> mv), and prints the
# result. On ccusage failure it falls back to stale cache content (better stale than
# blank). This is what makes repeated `blocks --json` calls collapse to one.
ccusage_cached() {
    local cache_name=$1; shift
    local ttl=$1; shift
    local cache_file
    cache_file="$(_ccusage_cache_dir)/${cache_name}"
    local now
    now=$(date +%s)

    # Fresh cache hit -> serve from disk, skip ccusage entirely.
    if [ -s "$cache_file" ]; then
        local age=$(( now - $(_file_mtime "$cache_file") ))
        if [ "$age" -ge 0 ] && [ "$age" -lt "$ttl" ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Cache miss/stale -> run ccusage (same assignment-from-substitution pattern the
    # rest of the script relies on, which is safe under `set -euo pipefail`).
    local cmd
    cmd=$(resolve_ccusage_cmd)
    local output
    output=$(cd ~ && $cmd "$@" --offline 2>/dev/null | awk '/^{/,0')

    if [ -n "$output" ] && [ "$output" != "null" ]; then
        printf '%s' "$output" > "${cache_file}.tmp" 2>/dev/null && \
            mv "${cache_file}.tmp" "$cache_file" 2>/dev/null || true
        printf '%s' "$output"
    elif [ -s "$cache_file" ]; then
        # ccusage unavailable/failed: degrade to stale data rather than nothing.
        cat "$cache_file"
    fi
}

# Convert Unix timestamp to ISO 8601 format
# Usage: timestamp_to_iso <timestamp>
# Returns: ISO 8601 string like "2025-10-01T15:00:00Z"
timestamp_to_iso() {
    local timestamp="${1:?Missing timestamp}"
    date -u -r "$timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
        date -u -d "@$timestamp" +"%Y-%m-%dT%H:%M:%SZ"
}

# Convert ISO 8601 timestamp to Unix timestamp
# Usage: iso_to_timestamp <iso_string>
# Returns: Unix timestamp (seconds since epoch)
iso_to_timestamp() {
    local iso_string="${1:?Missing ISO timestamp}"

    # Normalize "Z" suffix to "+0000" for BSD date compatibility
    local normalized_iso="${iso_string/Z/+0000}"

    # macOS (BSD date) - using -j prevents setting system time, -f specifies input format
    # Try both timezone formats: numeric offset (%z) and "Z" literal
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$normalized_iso" "+%s" 2>/dev/null || \
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_string" "+%s" 2>/dev/null || \
        # GNU date - simpler syntax (works with both Z and numeric offsets)
        date -d "$iso_string" "+%s" 2>/dev/null
}

# Calculate current Anthropic weekly period boundaries
# Anthropic uses fixed reset cycles (e.g., Wed 3pm → Wed 3pm in America/Vancouver timezone)
# Usage: get_anthropic_period <next_reset_timestamp>
# Returns: JSON with period start, end, and progress percentage
get_anthropic_period() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local current_ts=$(date +%s)

    # If we're past the reset time, calculate the next period
    if [[ $current_ts -ge $next_reset ]]; then
        # Calculate how many weeks past the reset we are
        local weeks_past=$(( (current_ts - next_reset) / WEEK_DURATION_SECONDS ))
        next_reset=$(( next_reset + (weeks_past + 1) * WEEK_DURATION_SECONDS ))
    # If we're before the reset, we might need to go back to find the current period
    elif [[ $current_ts -lt $(( next_reset - WEEK_DURATION_SECONDS )) ]]; then
        # Go back to find the right period
        while [[ $current_ts -lt $(( next_reset - WEEK_DURATION_SECONDS )) ]]; do
            next_reset=$(( next_reset - WEEK_DURATION_SECONDS ))
        done
    fi

    # Current period: [reset - 7 days, reset)
    local period_start=$(( next_reset - WEEK_DURATION_SECONDS ))
    local period_end=$next_reset

    # Calculate progress
    local elapsed=$(( current_ts - period_start ))
    local percent=$(( elapsed * 100 / WEEK_DURATION_SECONDS ))

    printf '{"start":%d,"end":%d,"percent":%d}\n' \
        "$period_start" "$period_end" "$percent"
}

# Calculate current daily period based on reset time
# Daily periods reset at the same time each day (e.g., 3pm daily for a 3pm weekly reset)
# Usage: get_daily_period <next_reset_timestamp>
# Returns: JSON with period start and current time
get_daily_period() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local current_ts=$(date +%s)

    # Extract the time-of-day from the reset timestamp
    # Strategy: Get the hour offset from midnight in the reset's timezone

    # First, get the weekly period to understand the reset schedule
    local weekly_period=$(get_anthropic_period "$next_reset")
    local weekly_start=$(echo "$weekly_period" | jq -r '.start')

    # Calculate seconds since start of week (day-of-week offset)
    local week_offset=$(( (current_ts - weekly_start) % WEEK_DURATION_SECONDS ))

    # Calculate today's reset time by finding the last occurrence of the daily reset hour
    # Start from the weekly reset time and add days until we're close to now
    local daily_reset=$weekly_start

    # Fast forward to approximately today (within this week)
    while [[ $((daily_reset + DAY_DURATION_SECONDS)) -le $current_ts ]]; do
        daily_reset=$((daily_reset + DAY_DURATION_SECONDS))
    done

    # If we're before today's reset time, use yesterday's reset
    if [[ $current_ts -lt $daily_reset ]]; then
        daily_reset=$((daily_reset - DAY_DURATION_SECONDS))
    fi

    printf '{"start":%d,"end":%d}\n' "$daily_reset" "$current_ts"
}

# Calculate daily cost using ccusage blocks
# Filters blocks from today's baseline reset time to current time
# Usage: get_daily_cost <next_reset_timestamp> [cache_duration_seconds]
# Returns: Total cost for current daily period
get_daily_cost() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local cache_duration="${2:-300}"  # Default 5 minutes, configurable

    # Get script directory (when sourced, use caller's directory)
    local utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cache_file="$utils_dir/../data/.daily_cache"
    local cache_duration_minutes=$((cache_duration / 60))

    # Get current daily period boundaries
    local period_data=$(get_daily_period "$next_reset")
    local period_start=$(echo "$period_data" | jq -r '.start')
    local period_end=$(echo "$period_data" | jq -r '.end')

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(find "$cache_file" -mmin -${cache_duration_minutes} 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            # Read cache and validate format: timestamp|period_start|period_end|daily_cost
            local cache_content=$(cat "$cache_file")
            local cached_period_start=$(echo "$cache_content" | cut -d'|' -f2)
            local cached_cost=$(echo "$cache_content" | cut -d'|' -f4)

            # Validate: same period AND valid number
            if [[ "$cached_period_start" == "$period_start" ]] && [[ "$cached_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "$cached_cost"
                return 0
            fi
            # Cache invalid (wrong period or corrupted) - fall through to recalculate
        fi
    fi

    # Convert period start to ISO 8601 format for comparison with ccusage
    local start_iso=$(timestamp_to_iso "$period_start")

    # Get all blocks from ccusage
    local blocks_data=$(ccusage_cached ".blocks_cache" "${CACHE_DURATION:-300}" blocks --json)

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0.00"
        return
    fi

    # Filter blocks where startTime >= period_start OR blocks that overlap the period
    # For overlapping blocks, include the full cost (conservative estimate)
    local period_end_iso=$(timestamp_to_iso "$period_end")
    local daily_cost=$(echo "$blocks_data" | jq -r --arg start_iso "$start_iso" --arg end_iso "$period_end_iso" '
        [.blocks[] |
         select(
           # Block starts within daily period
           (.startTime >= $start_iso) or
           # OR block is active and overlaps with daily period (endTime > period_start)
           (.endTime > $start_iso and .startTime < $end_iso)
         ) |
         .costUSD
        ] | add // 0
    ')

    # Format to 2 decimal places
    daily_cost=$(printf "%.2f" "$daily_cost")

    # Atomic cache write with period metadata
    # Format: timestamp|period_start|period_end|daily_cost
    local current_ts=$(date +%s)
    echo "${current_ts}|${period_start}|${period_end}|${daily_cost}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$daily_cost"
}

# Calculate official Anthropic weekly cost (matches console reset schedule)
# Uses ccusage blocks data filtered by official reset period
# Usage: get_official_weekly_cost <next_reset_timestamp> [cache_duration_seconds]
# Returns: Total cost for current Anthropic weekly period
get_official_weekly_cost() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local cache_duration="${2:-300}"  # Default 5 minutes, configurable

    # Get script directory (when sourced, use caller's directory)
    local utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cache_file="$utils_dir/../data/.official_weekly_cache"
    local cache_duration_minutes=$((cache_duration / 60))

    # Get current Anthropic period boundaries
    local period_data=$(get_anthropic_period "$next_reset")
    local period_start=$(echo "$period_data" | jq -r '.start')
    local period_end=$(echo "$period_data" | jq -r '.end')

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        # Fix: Use -mmin (minutes) instead of -mtime (days)
        local cache_age=$(find "$cache_file" -mmin -${cache_duration_minutes} 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            # Read cache and validate format: timestamp|period_start|period_end|weekly_cost
            local cache_content=$(cat "$cache_file")
            local cached_period_start=$(echo "$cache_content" | cut -d'|' -f2)
            local cached_cost=$(echo "$cache_content" | cut -d'|' -f4)

            # Validate: same period AND valid number
            if [[ "$cached_period_start" == "$period_start" ]] && [[ "$cached_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "$cached_cost"
                return 0
            fi
            # Cache invalid (wrong period or corrupted) - fall through to recalculate
        fi
    fi

    # Convert period start to ISO 8601 format for comparison with ccusage
    local start_iso=$(timestamp_to_iso "$period_start")

    # Get all blocks from ccusage
    local blocks_data=$(ccusage_cached ".blocks_cache" "${CACHE_DURATION:-300}" blocks --json)

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0.00"
        return
    fi

    # Filter blocks where startTime >= period_start and sum costs
    local weekly_cost=$(echo "$blocks_data" | jq -r --arg start_iso "$start_iso" '
        [.blocks[] |
         select(.startTime >= $start_iso) |
         .costUSD
        ] | add // 0
    ')

    # Format to 2 decimal places
    weekly_cost=$(printf "%.2f" "$weekly_cost")

    # Atomic cache write with period metadata
    # Format: timestamp|period_start|period_end|weekly_cost
    local current_ts=$(date +%s)
    echo "${current_ts}|${period_start}|${period_end}|${weekly_cost}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$weekly_cost"
}

# Calculate weekly recommended usage based on cycle start
# Returns static value for current cycle: weekly_avail_at_cycle_start / ceil(cycles_left_from_cycle_start)
# Usage: get_weekly_recommend <next_reset_timestamp> <weekly_limit> <weekly_baseline_pct> [cache_duration_seconds]
# Returns: Recommended daily usage percentage
get_weekly_recommend() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local weekly_limit="${2:?Missing weekly_limit}"
    local weekly_baseline_pct="${3:-0}"
    local cache_duration="${4:-300}"

    # Cache file per cycle
    local cache_file="${CACHE_DIR:-.}/.weekly_recommend_cache"

    # Get current cycle period
    local period_data=$(get_daily_period "$next_reset")
    local cycle_start=$(echo "$period_data" | jq -r '.start')

    # Check cache validity
    if [[ -f "$cache_file" ]]; then
        IFS='|' read -r cached_ts cached_cycle_start cached_value < "$cache_file"
        local current_ts=$(date +%s)

        # Cache valid if: same cycle AND within cache duration
        if [[ "$cached_cycle_start" == "$cycle_start" ]] && \
           [[ $((current_ts - cached_ts)) -lt $cache_duration ]] && \
           [[ "$cached_value" =~ ^[0-9]+$ ]]; then
            echo "$cached_value"
            return 0
        fi
    fi

    # Get weekly cost at cycle start by filtering blocks
    local cycle_start_iso=$(timestamp_to_iso "$cycle_start")
    local weekly_period=$(get_anthropic_period "$next_reset")
    local period_start=$(echo "$weekly_period" | jq -r '.start')
    local period_start_iso=$(timestamp_to_iso "$period_start")

    # Get blocks and filter up to cycle start
    local blocks_data=$(ccusage_cached ".blocks_cache" "${CACHE_DURATION:-300}" blocks --json)

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0"
        return
    fi

    # Calculate weekly cost at cycle start (from blocks before cycle started)
    local weekly_cost_at_cycle_start=$(echo "$blocks_data" | jq -r --arg start_iso "$period_start_iso" --arg end_iso "$cycle_start_iso" '
        [.blocks[] |
         select(
           (.startTime >= $start_iso) and
           (.startTime < $end_iso)
         ) |
         .costUSD
        ] | add // 0
    ')

    # Apply baseline offset (same as current week calculation)
    if [ "$(awk "BEGIN {print ($weekly_baseline_pct != 0)}")" = "1" ]; then
        local baseline_cost=$(awk "BEGIN {printf \"%.2f\", ($weekly_limit * $weekly_baseline_pct) / 100}")
        weekly_cost_at_cycle_start=$(awk "BEGIN {printf \"%.2f\", $weekly_cost_at_cycle_start + $baseline_cost}")
    fi

    # Calculate available budget at cycle start
    local avail_cost_at_start=$(awk "BEGIN {printf \"%.2f\", $weekly_limit - $weekly_cost_at_cycle_start}")
    local avail_pct_at_start=$(awk "BEGIN {printf \"%.2f\", ($avail_cost_at_start / $weekly_limit) * 100}")

    # Calculate cycles left from cycle start to reset
    local time_from_cycle_start_to_reset=$((next_reset - cycle_start))
    local cycles_left=$(awk "BEGIN {hours = $time_from_cycle_start_to_reset / 3600; cycles = hours / 24; print (cycles == int(cycles)) ? int(cycles) : int(cycles) + 1}")

    # Calculate recommend value
    local recommend_value=0
    if [ "$cycles_left" -gt 0 ]; then
        recommend_value=$(awk "BEGIN {printf \"%.0f\", $avail_pct_at_start / $cycles_left}")
    fi

    # Cache the result
    local current_ts=$(date +%s)
    echo "${current_ts}|${cycle_start}|${recommend_value}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$recommend_value"
}

# Calculate monthly period boundaries
# Returns current monthly period from payment_cycle_start_date to next month
# Usage: get_monthly_period <payment_cycle_start_timestamp>
# Returns: JSON with {start, end} timestamps
get_monthly_period() {
    local cycle_start="${1:?Missing payment_cycle_start timestamp}"

    # Get current time
    local current_time=$(date +%s)

    # Extract date components from cycle start
    local cycle_start_iso=$(timestamp_to_iso "$cycle_start")

    # Try GNU date first, then macOS date (supporting both Z and numeric timezone)
    local cycle_day=$(date -d "$cycle_start_iso" "+%d" 2>/dev/null)
    if [ -z "$cycle_day" ]; then
        cycle_day=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cycle_start_iso" "+%d" 2>/dev/null || \
                    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$cycle_start_iso" "+%d" 2>/dev/null)
    fi

    local cycle_time=$(date -d "$cycle_start_iso" "+%H:%M:%S" 2>/dev/null)
    if [ -z "$cycle_time" ]; then
        cycle_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cycle_start_iso" "+%H:%M:%S" 2>/dev/null || \
                     date -j -f "%Y-%m-%dT%H:%M:%S%z" "$cycle_start_iso" "+%H:%M:%S" 2>/dev/null)
    fi

    # Get current year and month
    local current_year=$(date -d "@$current_time" "+%Y" 2>/dev/null)
    if [ -z "$current_year" ]; then
        current_year=$(date -j -r "$current_time" "+%Y" 2>/dev/null)
    fi

    local current_month=$(date -d "@$current_time" "+%m" 2>/dev/null)
    if [ -z "$current_month" ]; then
        current_month=$(date -j -r "$current_time" "+%m" 2>/dev/null)
    fi

    # Build current month's cycle start (same day and time, current month)
    local this_month_cycle=$(date -d "${current_year}-${current_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null || \
                              date -j -f "%Y-%m-%d %H:%M:%S" "${current_year}-${current_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null)

    # If current time is before this month's cycle start, use previous month
    if [ "$current_time" -lt "$this_month_cycle" ]; then
        # Go back one month
        if [ "$current_month" = "01" ]; then
            current_year=$((current_year - 1))
            current_month="12"
        else
            current_month=$(printf "%02d" $((10#$current_month - 1)))
        fi
        this_month_cycle=$(date -d "${current_year}-${current_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null || \
                            date -j -f "%Y-%m-%d %H:%M:%S" "${current_year}-${current_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null)
    fi

    # Calculate next month's cycle start
    local next_year="$current_year"
    local next_month=$(printf "%02d" $((10#$current_month + 1)))
    if [ "$next_month" = "13" ]; then
        next_year=$((current_year + 1))
        next_month="01"
    fi

    local next_month_cycle=$(date -d "${next_year}-${next_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null || \
                              date -j -f "%Y-%m-%d %H:%M:%S" "${next_year}-${next_month}-${cycle_day} ${cycle_time}" "+%s" 2>/dev/null)

    # Return period boundaries
    echo "{\"start\": $this_month_cycle, \"end\": $next_month_cycle}"
}

# Calculate monthly cost using ccusage blocks
# Filters blocks from payment cycle start to current time
# Usage: get_monthly_cost <payment_cycle_start_timestamp> [cache_duration_seconds]
# Returns: Total cost for current monthly period
get_monthly_cost() {
    local cycle_start="${1:?Missing payment_cycle_start timestamp}"
    local cache_duration="${2:-300}"  # Default 5 minutes

    # Get script directory
    local utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cache_file="$utils_dir/../data/.monthly_cache"
    local cache_duration_minutes=$((cache_duration / 60))

    # Get current monthly period boundaries
    local period_data=$(get_monthly_period "$cycle_start")
    local period_start=$(echo "$period_data" | jq -r '.start')
    local period_end=$(echo "$period_data" | jq -r '.end')

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(find "$cache_file" -mmin -${cache_duration_minutes} 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            # Read cache and validate format: timestamp|period_start|period_end|monthly_cost
            local cache_content=$(cat "$cache_file")
            local cached_period_start=$(echo "$cache_content" | cut -d'|' -f2)
            local cached_cost=$(echo "$cache_content" | cut -d'|' -f4)

            # Validate: same period AND valid number
            if [[ "$cached_period_start" == "$period_start" ]] && [[ "$cached_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "$cached_cost"
                return 0
            fi
        fi
    fi

    # Cache miss - calculate from ccusage
    # Convert timestamps to ISO format for ccusage
    local start_iso=$(timestamp_to_iso "$period_start")
    local end_iso=$(timestamp_to_iso "$period_end")

    # Get all blocks and filter by monthly period
    local blocks_data=$(ccusage_cached ".blocks_cache" "${CACHE_DURATION:-300}" blocks --json)

    # Filter blocks within period and sum costs
    local monthly_cost=$(echo "$blocks_data" | jq -r --arg start "$start_iso" --arg end "$end_iso" '
        [.blocks[]? |
         select(.startTime >= $start and .startTime < $end) |
         .costUSD // 0
        ] | add // 0
    ')

    # Format to 2 decimal places
    monthly_cost=$(printf "%.2f" "$monthly_cost")

    # Atomic cache write with period metadata
    local current_ts=$(date +%s)
    echo "${current_ts}|${period_start}|${period_end}|${monthly_cost}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$monthly_cost"
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f timestamp_to_iso
    export -f iso_to_timestamp
    export -f get_anthropic_period
    export -f get_daily_period
    export -f get_monthly_period
    export -f get_daily_cost
    export -f get_official_weekly_cost
    export -f get_monthly_cost
    export -f get_weekly_recommend
fi
