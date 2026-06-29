# Claude Statusline - Development Guide

## Project Overview

Real-time usage tracking statusline for Claude Code using shim architecture.

**Repository**: `~/Documents/Projects/cc-statusline`
**Active Branch**: `feature-daily-usage`
**Remotes**:
- Dev fork: `git@github.com:hell0github/claude-statusline-dev.git`
- Production: `https://github.com/MatteoSchifano/claude-statusline.git`

## Development Principles

### Open-Closed Principle
**All configuration values MUST be loaded from config files. NEVER hardcode values in scripts or comments.**

**Rules:**
1. **No hardcoded config values in code**
   - ❌ `LAYER1_THRESHOLD=14.29`
   - ✅ `LAYER1_THRESHOLD=$(calculate from config multiplier)`

2. **No hardcoded values in comments**
   - ❌ `# Layer 1: 0-14.29% actual`
   - ✅ `# Layer 1: 0-1.0×base threshold`

3. **Config-driven thresholds**
   - All layer thresholds use `threshold_multiplier` notation
   - Base thresholds calculated at runtime from limits or dynamic values
   - Formula: `layer_threshold = base_threshold × threshold_multiplier`

4. **Examples:**
   ```bash
   # 5-hour window: base = COST_LIMIT
   LAYER1_THRESHOLD=$(awk "BEGIN {print $COST_LIMIT * $LAYER1_THRESHOLD_MULT}")

   # Daily static: base = weekly_limit / 7
   DAILY_BASE=$(awk "BEGIN {print ($WEEKLY_LIMIT / 7.0) / $WEEKLY_LIMIT * 100}")

   # Daily dynamic: base = recommend value
   DAILY_BASE=$WEEKLY_DISPLAY_VALUE

   # Context: base = CONTEXT_LIMIT
   CTX_LAYER1=$(awk "BEGIN {print $CONTEXT_LIMIT * $CTX_LAYER1_THRESHOLD_MULT}")
   ```

**Benefits:**
- Single source of truth (config files)
- Easy to adjust thresholds without code changes
- Consistent behavior across all sections
- Self-documenting through config structure

## File Structure

```
~/Documents/Projects/cc-statusline/
├── src/
│   ├── statusline.sh              # Main implementation (3-line render)
│   ├── statusline-utils.sh        # Daily/weekly tracking utilities
│   ├── statusline-cache.sh        # Cache dependency tracking
│   ├── statusline-layers.sh       # Multi-layer metric calculations
│   └── ccbranch.sh                # Companion: rename current branch
├── tools/
│   └── calibrate_weekly_usage.sh  # Weekly usage calibration tool
├── config/
│   ├── config.json                # User config (gitignored)
│   └── config.example.json        # Template with defaults
├── data/                           # Runtime cache (gitignored)
│   ├── .daily_cache
│   ├── .official_weekly_cache
│   └── .pr_cache                  # Open-PR lookup cache (gh)
├── install.sh
├── README.md
├── CLAUDE.md
└── .gitignore

~/.claude/
└── statusline.sh                   # 2-line shim → delegates to src/statusline.sh
```

## Features

### Layout (3 lines)
- **Line 1 — identity**: directory + git branch + worktree toggle (`[ ]`/`[X]`)
- **Line 2 — work links**: Linear issue (id parsed from branch) + open PR (`gh`, cached), with a `＋ link Linear` CTA when the branch has no id; OSC 8 hyperlinks via `osc8_link()`
- **Line 3 — usage/budget**: context, weekly %, daily, timer

### Core Features
- **5-hour window tracker** - Current session cost with projection
- **Daily usage tracker** - 24-hour cycle aligned with weekly reset (2-layer: normal/exceeding)
- **Weekly usage tracker** - Full week percentage (rate-limit bar removed)
- **Context window tracker** - Token usage monitoring
- **Timer** - Countdown to next reset
- **Git / Linear / PR** - Branch + worktree detection, Linear issue link, open-PR link (Stage 1 collects via `git -C`, `grep` on branch, `get_pr_for_branch()`)
- **Branch rename** - `src/ccbranch.sh` companion command (statusline is display-only)

### Key Implementations
- **Shim architecture** - Stable interface (`~/.claude/statusline.sh`) delegates to implementation
- **Multi-layer progress bars** - Auto-scaled visualization (different multipliers per threshold)
- **ccusage_r scheme** - Matches Anthropic console % (filters by official reset schedule)
- **Daily cost tracking** - `get_daily_cost()` with caching, aligned to weekly reset time
- **Daily projection** - Uses 5-hour window: `daily_cost - window_cost + projected_window_cost`
- **Daily recommendation** - Stable budget recommendation, updates only at daily cycle reset
- **Conditional rendering** - Only computes enabled sections for performance
- **Configurable colors** - Per-layer color customization

### Daily Recommendation Logic

**Formula**: `(weekly_limit - usage_from_weekly_start_to_daily_cycle_start) / cycles_left`

**Behavior**:
- **Stable throughout each daily cycle** - Only updates at daily reset (e.g., 3pm)
- **Cycle-aligned** - Uses usage up to current daily cycle start, not current time
- **Baseline-independent** - Uses raw weekly cost (excludes baseline) for full $850 availability

**Example scenarios**:

**Day 1 (right after weekly reset at 3pm):**
- Weekly start: 3pm Day 1
- Daily cycle start: 3pm Day 1 (same!)
- Usage from weekly→daily start: **$0**
- Available: $850 - $0 = **$850**
- Recommend: $850 / 7 = **$121/day**

**Day 3 (at 4pm):**
- Weekly start: 3pm Day 1
- Daily cycle start: 3pm Day 3
- Usage from weekly→daily start: Day 1 + Day 2 costs
- Available: $850 - (Day 1 + Day 2)
- Recommend: available / 5 remaining days
- **Stays at this value from 3pm Day 3 until 3pm Day 4**

**Rendering precision**:
- Dollar amount calculated from precise division: `$850 / 7 = $121.43 → $121`
- Percentage shown as rounded value: `14.29% → 14%`
- Avoids rounding error: `14% × $850 = $119` ❌ vs `$850 / 7 = $121` ✓

## Configuration

**Path**: `config/config.json`

**Key settings**:
- `user.plan` - pro/max5x/max20x
- `limits.weekly`, `limits.cost` - Usage limits
- `multi_layer` - 3-layer thresholds + colors for weekly/5-hour window
- `daily_layer` - 2-layer thresholds + colors (14.29% normal, 21.44% exceeding)
- `sections.show_*` - Toggle individual sections
- `tracking.weekly_scheme` - "ccusage" (ISO week) or "ccusage_r" (official reset)
- `tracking.official_reset_date` - Required for ccusage_r and daily tracking

## Tools

### Weekly Usage Calibrator

**Path**: `tools/calibrate_weekly_usage.sh`

Aligns statusline weekly tracking with Anthropic's official usage percentage.

**Purpose**: Compensates for untracked costs:
- Deleted/compacted transcripts (clear/compact commands)
- Extended context usage (Sonnet 4 [1m] pricing differences)
- Any costs not captured by ccusage

**Requirements**:
- `tracking.weekly_scheme` must be set to `"ccusage_r"`
- `tracking.official_reset_date` must be configured

**Usage**:

**Option 1: Slash Command (Recommended)**
```bash
# Global slash command available in all Claude Code sessions
/calibrate_weekly_usage_baseline 18.5
```

**Option 2: Direct Script**
```bash
# Run script directly from project root
tools/calibrate_weekly_usage.sh 18.5

# Example output:
#   Official Usage (Anthropic): 18.5%
#   Tracked Usage (ccusage_r):  12.3%
#   Gap (untracked costs):      6.2%
#
#   Baseline updated: 10% → 6.2%
#   Statusline will now show: 18.5%
```

**When to calibrate**:
- After weekly reset (to zero out baseline if needed)
- When you notice drift between statusline and console
- After significant transcript cleanup operations
- Weekly as a maintenance routine

**Slash Command Setup**:
The calibrator is available as a global slash command in `~/.claude/commands/calibrate_weekly_usage_baseline.md`. This makes it accessible from any Claude Code session without needing to navigate to the project directory.

## Development

### Testing
```bash
# Test manually
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | src/statusline.sh

# Test daily functions
source src/statusline-utils.sh
get_daily_cost "2025-10-08T15:00:00-07:00"

# Test calibrator
tools/calibrate_weekly_usage.sh 15.0
```

### Path Conventions
- Always use relative paths from `$SCRIPT_DIR`
- Config: `$SCRIPT_DIR/../config/config.json`
- Data: `$SCRIPT_DIR/../data/filename`

### Git Workflow

**IMPORTANT: Commit Authorship Policy**
- **DO NOT** include Claude Code co-authorship in commit messages
- **DO NOT** add `🤖 Generated with [Claude Code](...)` footer
- **DO NOT** add `Co-Authored-By: Claude <noreply@anthropic.com>` trailer
- Keep commits clean and professional

**Commit conventions**:
- `feat:` New features
- `fix:` Bug fixes
- `refactor:` Code reorganization
- `docs:` Documentation
- `chore:` Maintenance

### Recent Updates

**v2.4** (2026-06-29) - 3-Line Layout + Workflow Context
- Restructured output into three lines: identity / work links / usage
- Line 1: directory + git branch + worktree toggle (`[ ]`/`[X]`)
- Line 2: Linear issue (id from branch) + open PR (`gh`, cached), OSC 8 links with text fallback, `＋ link Linear` CTA when no id
- Removed the weekly rate-limit bar (kept `weekly N%`); token-rate and sessions off by default
- New config: `sections.show_git`/`show_work_links` + `integrations` block (`linear.workspace`, `clickable_links`, `pr_cache_seconds`)
- Added `src/ccbranch.sh` companion to rename the current branch (statusline is display-only)

**v2.3** (2025-10-08) - Daily Recommendation Fix
- Fixed recommend calculation to use correct cycle-aligned logic
- Formula: `(weekly_limit - usage_from_weekly_start_to_daily_cycle_start) / cycles_left`
- Stable recommendations that update only at daily reset (3pm)
- Baseline excluded from recommendation (uses raw weekly cost)
- Fixed rounding precision: calculate dollar amount from exact division

**v2.2** (2025-10-06) - Weekly Usage Calibration Tool
- `tools/calibrate_weekly_usage.sh` - Aligns tracking with official usage
- Compensates for untracked costs (deleted transcripts, extended context)
- Interactive baseline adjustment with safety validations

**v2.1** (2025-10-05) - Daily Usage Tracking
- Two-layer daily system (14.29% normal, 21.44% exceeding)
- 5-hour window projection integration
- `get_daily_cost()` with caching

**v2.0** (2025-10-05) - Daily Foundation
- `get_daily_period()` function
- Conditional section rendering
- Configurable layer colors

**v1.5** (2025-10-02) - Project Reorganization
- src/, config/, data/ structure
- 2-line shim architecture

---

**Last Updated**: 2025-10-08
