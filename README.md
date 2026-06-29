# Claude Statusline

A custom statusline for [Claude Code 2.x](https://claude.com/claude-code) that provides real-time usage tracking with an intelligent multi-layer progress visualization, helping you stay aware of context windows, costs, and session limits.

## Features

### Core Tracking Features
- **5-hour window tracker** - Real-time cost monitoring with burn-rate based projection and 3-layer visualization
- **Daily usage tracker** - 24-hour cycle aligned with weekly reset, shows % of weekly limit with end-of-day projection
- **Weekly usage tracker** - Multiple display modes: usage %, available %, or recommended daily usage
- **Monthly cost tracker** - Total spending from billing cycle start date (configurable)
- **Context window tracker** - 3-layer visualization showing cached vs fresh tokens, supports extended context (>168k)
- **Token burn rate** - Real-time tokens/min indicator based on billable tokens (off by default)
- **Session timer** - Countdown to next 5-hour window reset with current/reset time display
- **Active sessions** - Concurrent Claude Code project counter (off by default)

### Workflow Features (3-line layout)
- **Git branch + worktree** - Line 1 shows the current branch with a `[ ]`/`[X]` toggle that flags whether you're in a linked git worktree
- **Linear issue link** - Parses the Linear issue id from the branch name (e.g. `feature/YR-198_...` → `YR-198`) and renders a clickable link; shows a `＋ link Linear` CTA when the branch carries no id
- **Open PR link** - Looks up the current branch's open PR via `gh` (cached on disk) and renders a clickable `PR #N`
- **Clickable links** - OSC 8 terminal hyperlinks for Linear/PR (iTerm2, WezTerm, Kitty, VS Code), with graceful text fallback
- **Branch rename helper** - Companion `ccbranch` command renames the current branch (the statusline is display-only and cannot)

### Advanced Features
- **Intelligent weekly calibration** - Compensates for untracked costs (deleted transcripts, extended context)
- **Multi-layer progression system** - Config-driven thresholds with auto-scaled visualization per layer
- **Weekly display modes** - Choose between usage %, available %, or recommended daily % to finish allocated budget
- **Daily projection integration** - Combines 5-hour window projection with daily tracking for accurate end-of-day estimates
- **Unified cache system** - Smart dependency tracking invalidates caches when config changes
- **Three-stage pipeline** - Clean architecture: Data Collection → Computation → Rendering
- **Conditional rendering** - Only computes enabled sections for optimal performance
- **Modular utilities** - Separate layer calculations, caching, and time tracking modules

### Technical Highlights
- **Lightweight bash implementation** - Pure shell with minimal dependencies (jq, ccusage)
- **Privacy-first design** - Personal config and cache excluded from version control
- **Atomic cache writes** - Crash-safe tmp → mv pattern for all cache operations
- **Comprehensive config validation** - Startup validation prevents runtime errors
- **Tested on Max20 plan and macOS** - Compatible with Linux and WSL

## Platform Support

- **macOS** - ✅ Fully tested and supported
- **Linux** - ✅ Supported (requires bash, jq, npm)
- **Windows** - ⚠️ WSL or Git Bash only (not native CMD/PowerShell)

## Example Output

The statusline renders on **three lines**: identity, work links, then usage/budget.

### Branch with a Linear id + open PR
```
yourang  ⎇ feature/YR-198_custom-fields  [ ]
LIN YR-198  |  PR #1391
Opus 4.8 45k [████████░░]  |  weekly 18%  |  daily [██░│░░░░░░] 6/12%  |  3h 42m
```

### Branch without a Linear id (CTA) inside a worktree
```
yourang  ⎇ claude/shadcn-chat-refactor  [X]
＋ link Linear  |  PR —
Opus 4.8 45k [████████░░]  |  weekly 18%  |  42%
```

**Line breakdown:**
- **Line 1 — identity**
  - `yourang` - Current project directory (bright orange)
  - `⎇ feature/YR-198_...` - Current git branch
  - `[ ]` / `[X]` - Worktree toggle: `[X]` when inside a linked git worktree, `[ ]` in the main worktree
- **Line 2 — work links**
  - `LIN YR-198` - Linear issue parsed from the branch name (clickable link when `integrations.linear.workspace` is set)
  - `＋ link Linear` - CTA shown instead when the branch carries no Linear id
  - `PR #1391` - Open PR for the branch via `gh` (clickable); `PR —` when there is none
- **Line 3 — usage / budget**
  - `45k [████████░░]` - Context: cached+fresh tokens with 3-layer progress bar (prefixed by the model name)
  - `weekly 18%` - Weekly rate-limit percentage (the `[█░░░]` bar was intentionally removed)
  - `daily [██░│░░░░░░] 6/12%` - Daily: actual/recommend % (combined mode)
  - `3h 42m` / `42%` - 5-hour window reset countdown / percentage

> Token burn rate (`/min`) and the active-sessions counter (`×N`) are disabled by default but can be re-enabled via `sections.show_token_rate` / `sections.show_sessions`.

## Installation

### Quick Install (Recommended)

One command to install everything:

```bash
curl -sSL https://raw.githubusercontent.com/hell0github/claude-statusline/main/install.sh | bash
```

The installer will:
- ✅ Check dependencies (jq, ccusage)
- ✅ Copy files to ~/.claude/
- ✅ Prompt for your plan (pro/max5x/max20x)
- ✅ Ask permission before modifying settings.json
- ✅ Create backup of existing settings
- ✅ Guide you through setup

### Manual Installation

**Prerequisites:** [Claude Code](https://claude.com/claude-code), `jq` (`brew install jq`), `ccusage` (`npm install -g ccusage`)

```bash
# Clone repository to Projects directory
git clone https://github.com/hell0github/claude-statusline.git ~/Projects/cc-statusline
cd ~/Projects/cc-statusline

# Run installer (recommended)
./install.sh

# OR set up manually:
# 1. Create shim in ~/.claude/
cat > ~/.claude/statusline.sh << 'EOF'
#!/bin/bash
exec "$HOME/Projects/cc-statusline/src/statusline.sh" "$@"
EOF
chmod +x ~/.claude/statusline.sh

# 2. Copy example config
cp config/config.example.json config/config.json

# 3. Edit config (set your plan)
nano config/config.json

# 4. Add to ~/.claude/settings.json:
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}

# Restart Claude Code
```

## Configuration

Edit `~/Documents/Projects/cc-statusline/config/config.json` to customize your statusline:

### Essential Settings
- **`user.plan`** - Set to `"pro"`, `"max5x"`, or `"max20x"` (your subscription tier)
- **`limits.weekly`** - Weekly cost limits per plan (pro: $300, max5x: $500, max20x: $850)
  - Note: `pro` and `max5x` limits are estimated - only `max20x` has been verified
- **`limits.cost`** - 5-hour window cost limit (default: $140)
- **`limits.context`** - Context window limit in thousands (default: 168k)

### Display Configuration
- **`display.bar_length`** - Progress bar length (default: 10 blocks)
- **`colors.*`** - Customize ANSI color codes for each element (green, orange, red, pink, cyan, etc.)

### Multi-Layer Systems
- **`multi_layer.*`** - 5-hour window layers (3-layer system)
  - `layer1/2/3.threshold_multiplier` - Thresholds relative to cost_limit (default: 0.3/0.5/1.0)
  - `layer1/2/3.color` - Color names for each layer (default: green/orange/red)

- **`daily_layer.*`** - Daily usage layers (2-layer system)
  - `layer1/2.threshold_multiplier` - Thresholds relative to base (default: 1.0/1.5)
  - `layer1/2.color` - Color names (default: green/bright_orange)
  - Base threshold is dynamic: weekly_limit/7 (static mode) or recommend value (dynamic mode)

- **`context_layer.*`** - Context window layers (3-layer system)
  - `layer1/2/3.threshold_multiplier` - Thresholds relative to context_limit (default: 1.0/2.0/3.0)
  - `layer1/2/3.color` - Color names (default: dim_pink/dim_orange/dim_red)
  - Allows tracking beyond nominal 168k limit

### Section Toggles
- **`sections.show_directory`** - Project name display (default: true)
- **`sections.show_context`** - Context window tracker (default: true)
- **`sections.show_five_hour_window`** - 5-hour cost window (default: true)
- **`sections.show_daily`** - Daily usage tracker (default: true, requires `official_reset_date`)
- **`sections.show_weekly`** - Weekly usage display (default: true)
- **`sections.show_monthly`** - Monthly total cost (default: false, requires `payment_cycle_start_date`)
- **`sections.show_timer`** - Reset countdown (default: true)
- **`sections.show_token_rate`** - Token burn rate / `/min` (default: false)
- **`sections.show_sessions`** - Active session counter / `×N` (default: false)
- **`sections.show_git`** - Line 1 git branch + worktree toggle (default: true)
- **`sections.show_work_links`** - Line 2 Linear issue + open PR (default: true)

### Integrations (Git / Linear / PR)
- **`integrations.linear.workspace`** - Linear workspace slug used to build issue links.
  Find it in any Linear URL: `https://linear.app/<workspace>/issue/...`. The issue id is parsed
  from the branch name (e.g. `feature/YR-198_...` → `YR-198`). Leave empty to render the id/CTA
  as plain, non-clickable text.
- **`integrations.clickable_links`** - Emit OSC 8 terminal hyperlinks for the Linear issue and PR
  (default: true). Clickable in iTerm2, WezTerm, Kitty, and the VS Code terminal; set to `false`
  if your terminal renders raw escape codes.
- **`integrations.pr_cache_seconds`** - How long the open-PR lookup (`gh pr view`) is cached on disk
  (default: 90). Keeps the statusline fast by avoiding a network call on every render.
  Requires the GitHub CLI (`gh`) to be installed and authenticated; degrades silently otherwise.

### Weekly Display Modes
- **`sections.weekly_display_mode`** - How to display weekly section:
  - `"usage"` - Shows weekly usage % (default, label: "weekly")
  - `"avail"` - Shows available % remaining (label: "avail")
  - `"recommend"` - Shows recommended daily % to finish allocated budget (label: "recom")
    - Formula: `(weekly_limit - usage_from_weekly_start_to_daily_cycle_start) / cycles_left`
    - Stable throughout each daily cycle (e.g., 3pm→3pm), updates only at daily reset
    - Uses raw weekly cost (excludes baseline) for full limit availability
    - Combines with daily tracker to show: `daily [bar] actual/recommend% $actual/$recommend`
    - Example: Day 1 at 3pm: $850 / 7 days = $121/day (14%)

### Tracking Configuration
- **`tracking.weekly_scheme`** - Weekly calculation method:
  - `"ccusage"` - ISO weeks Monday-Sunday (default)
  - `"ccusage_r"` - Official Anthropic reset schedule (requires `official_reset_date`)

- **`tracking.official_reset_date`** - ISO 8601 timestamp for Anthropic weekly reset
  - Format: `"2025-10-08T15:00:00-07:00"` (from console "Resets Oct 8, 3pm" in America/Vancouver)
  - Required for: daily tracking, ccusage_r scheme, recommend mode

- **`tracking.payment_cycle_start_date`** - ISO 8601 timestamp for billing cycle start
  - Format: `"2025-10-01T15:00:00-07:00"` (date is cycle start, time copied from official_reset_date)
  - Required for: monthly cost tracking (show_monthly)

- **`tracking.weekly_baseline_percent`** - Compensation for untracked costs (default: 0)
  - Adds fixed % to weekly usage to account for deleted transcripts
  - Use calibration tool to calculate: `tools/calibrate_weekly_usage.sh <official_%>`

- **`tracking.cache_duration_seconds`** - Cache TTL in seconds (default: 300 = 5 minutes)
  - Controls how often ccusage_r queries run
  - Lower values = more responsive but more API calls

See `config/config.example.json` for all available options with detailed comments.

## Branch Rename Helper (`ccbranch`)

The statusline is **display-only** — it receives JSON on stdin and prints text, so it cannot
accept keystrokes to edit the branch shown on line 1. Branch renaming lives in a tiny companion
command instead:

```bash
ccbranch <new-name>     # rename the current branch (git branch -m)
ccbranch --help         # usage
```

Add a shell alias so it's available everywhere:

```bash
# ~/.zshrc or ~/.bashrc
alias ccbranch="$HOME/Documents/Projects/cc-statusline/src/ccbranch.sh"
```

`ccbranch` renames locally only. To update the remote afterwards:

```bash
git push origin -u <new-name>
```

## Handling Untracked Costs (Deleted Transcripts)

**Problem**: When you use Claude Code's `clear` or `compact` commands to delete transcripts, the usage data is permanently removed from ccusage tracking (which reads from transcript files). This creates a discrepancy:
- **Anthropic Console**: Still shows full usage (server-side records)
- **Statusline**: Shows lower percentage (missing deleted transcript costs)

Additionally, extended context usage (e.g., Sonnet 4 [1m]) may have pricing differences that create tracking gaps.

**Solution**: Use the built-in calibration tool to automatically calculate and apply the baseline offset.

### Automated Calibration (Recommended)

**Option 1: Slash Command** (Available in any Claude Code session)
```bash
# From any project
/calibrate_weekly_usage_baseline 18.5
```

**Option 2: Direct Script**
```bash
# From statusline project directory
cd ~/Projects/cc-statusline
tools/calibrate_weekly_usage.sh 18.5
```

**What it does:**
1. Reads your current tracked usage from ccusage_r
2. Calculates the gap: `official_% - tracked_%`
3. Updates `tracking.weekly_baseline_percent` in config
4. Clears cache to force refresh

**When to calibrate:**
- After weekly reset (to zero out baseline if needed)
- When you notice drift between statusline and console
- After significant transcript cleanup operations
- Weekly as a maintenance routine

**Prerequisites:**
- `tracking.weekly_scheme` must be `"ccusage_r"`
- `tracking.official_reset_date` must be configured

### Manual Calibration (Alternative)

If you prefer manual configuration:

1. **Check Anthropic console** for current weekly usage %
2. **Check statusline** for current weekly usage %
3. **Calculate gap**: `console_% - statusline_%`
4. **Update config**:
   ```json
   {
     "tracking": {
       "weekly_baseline_percent": 5
     }
   }
   ```

**Example:**
- Console shows: **18.5%**
- Statusline shows: **12.3%**
- Gap: `18.5% - 12.3% = 6.2%`
- Set: `"weekly_baseline_percent": 6.2`
- Result: Statusline now shows **18.5%** ✓

**Note**: The baseline applies to **all tracking schemes** (both `ccusage` and `ccusage_r`). If you don't delete transcripts, keep this at `0` (default).

## Daily and Weekly Usage Tracking Calibration

**Note**: By default, weekly tracking uses ISO weeks (Monday-Sunday) via ccusage. This may show different percentages than the Anthropic console, which uses custom reset cycles (e.g., Wednesday 3pm → Wednesday 3pm).

### Configure Official Reset Schedule (Enables Daily Tracker)

Setting the official reset date **enables two features**:
1. **Daily usage tracking** - 24-hour cycle tracker with end-of-day projection
2. **Weekly tracking calibration** - Match Anthropic console percentage exactly (when using `ccusage_r` scheme)

**Setup steps:**

1. **Find your reset date** at [console.anthropic.com](https://console.anthropic.com):
   - Go to Usage tab
   - Look for "Resets [date/time]" text (e.g., "Resets Oct 8, 3pm")

2. **Update your config** (`~/Projects/cc-statusline/config/config.json`):
```json
{
  "tracking": {
    "weekly_scheme": "ccusage_r",
    "official_reset_date": "2025-10-08T15:00:00-07:00"
  }
}
```

3. **Format guide**:
   - `YYYY-MM-DDTHH:MM:SS±HH:MM`
   - Example: "Oct 8, 3pm Vancouver" → `2025-10-08T15:00:00-07:00` (PDT = UTC-7)
   - You only need to update this once; it auto-calculates future periods

**Results**:
- Daily tracker will appear in your statusline showing today's usage as % of weekly limit
- Weekly percentage will match Anthropic console (if using `ccusage_r` scheme)

**Note**: Daily tracking works with either `ccusage` or `ccusage_r` weekly schemes - only `official_reset_date` is required.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Statusline doesn't appear | `chmod +x ~/.claude/statusline.sh` and restart Claude Code |
| "jq: command not found" | `brew install jq` (macOS) or `sudo apt-get install jq` (Linux) |
| "Window tracking unavailable" | `npm install -g ccusage` |
| Wrong usage data | Update `user.plan` in config, verify with `ccusage blocks --active` |
| Colors not working | Check terminal 256-color support |

## Architecture

### Shim Pattern
This plugin uses a **shim architecture** for clean separation and stability:

```
Claude Code → ~/.claude/statusline.sh (2-line shim)
                      ↓
              ~/Projects/cc-statusline/src/statusline.sh (implementation)
```

**Benefits:**
- Stable interface: Claude Code always calls the same shim path
- Flexible implementation: Can reorganize code without reconfiguring Claude
- Easy updates: Git pull updates implementation without touching shim

### Three-Stage Pipeline
The statusline follows a clean data flow architecture:

```
┌─────────────────────┐
│  STAGE 1: COLLECT   │  Parse input, call ccusage, read transcripts
│                     │  • Conditional: only for enabled sections
│                     │  • All external process calls happen here
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│  STAGE 2: COMPUTE   │  Calculate percentages, layers, projections
│                     │  • Apply layer calculation functions
│                     │  • Pure computation, no external calls
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│  STAGE 3: RENDER    │  Build progress bars, apply colors, format
│                     │  • Assemble sections with separators
│                     │  • Output final statusline string
└─────────────────────┘
```

**Benefits:**
- Clear separation of concerns
- Easier to test individual stages
- Obvious data dependencies
- Conditional evaluation for performance

### Modular Utilities
- **statusline-utils.sh** - Time period calculations (ISO↔Unix, daily/weekly/monthly boundaries)
- **statusline-layers.sh** - Generic 2-layer and 3-layer visual scale calculations
- **statusline-cache.sh** - Unified cache management with dependency tracking

### Caching Strategy
Smart caching system with multiple invalidation triggers:
- **Period change** - Daily/weekly/monthly boundary crossed
- **Time-based** - Cache older than configured duration (default: 5 min)
- **Dependency change** - Config values affecting calculations changed (weekly_limit, baseline)
- **Data corruption** - Cached value fails validation

All cache writes are atomic (tmp → mv) for crash safety.

## File Structure

```
~/Projects/cc-statusline/          # Installation directory
├── src/                           # Source code
│   ├── statusline.sh             # Main implementation (3-stage pipeline)
│   ├── statusline-utils.sh       # Time tracking utilities (daily/weekly/monthly)
│   ├── statusline-layers.sh      # Generic layer calculation functions
│   └── statusline-cache.sh       # Unified cache management with dependency tracking
├── config/                        # Configuration
│   ├── config.json               # Your settings (gitignored)
│   └── config.example.json       # Template with defaults
├── data/                          # Runtime cache (gitignored)
│   ├── .daily_cache              # Daily cost cache (period-aware)
│   ├── .official_weekly_cache    # Weekly cost cache (ccusage_r scheme)
│   ├── .monthly_cache            # Monthly cost cache (billing cycle)
│   ├── .weekly_recommend_cache   # Recommend value cache (cycle-aware)
│   ├── .cache_deps               # Config dependency tracking (invalidation)
│   └── statusline-data.json      # Legacy cache (deprecated)
├── tools/                         # Utilities
│   └── calibrate_weekly_usage.sh # Weekly usage calibration tool
├── example/                       # Example screenshots
│   └── statusline.png            # Visual reference
├── install.sh                     # Automated installer
├── README.md                      # This file
├── CLAUDE.md                      # Development guide (architecture, conventions)
├── LICENSE                        # MIT License
└── .gitignore

~/.claude/
├── statusline.sh                 # 2-line shim (delegates to src/statusline.sh)
└── commands/                      # Slash commands (optional)
    └── calibrate_weekly_usage_baseline.md  # Calibration slash command
```

**Key components:**
- **statusline.sh** - Entry point, config validation, 3-stage rendering pipeline
- **statusline-utils.sh** - Period calculations (daily/weekly/monthly), ccusage_r support
- **statusline-layers.sh** - Reusable 2-layer and 3-layer metric calculations
- **statusline-cache.sh** - Centralized cache validation with config dependency tracking
- **Caches** - Atomic writes (tmp → mv), period-aware validation, dependency invalidation
- **Shim** - Stable interface in ~/.claude/, implementation in ~/Projects/cc-statusline/

## License

MIT License - See [LICENSE](LICENSE) file for details.

Free to use, modify, and distribute. No warranty provided.

## For Developers

### Quick Start

Contributing or modifying the plugin? See [CLAUDE.md](CLAUDE.md) for comprehensive development documentation:

- **Architecture** - Shim pattern, 3-stage pipeline, modular utilities
- **Development principles** - Open-closed principle, config-driven design
- **Testing** - Manual testing commands, function testing procedures
- **Git workflow** - Commit conventions, branching strategy
- **Path conventions** - Relative path standards, script directory references
- **Recent updates** - Version history and feature changelog

### Key Principles

**Open-Closed Principle:**
- All config values loaded from JSON - NEVER hardcode in scripts or comments
- Use threshold multipliers, not absolute values
- Single source of truth for all configuration

**Examples:**
```bash
# ❌ Bad: Hardcoded threshold
LAYER1_THRESHOLD=14.29

# ✅ Good: Config-driven calculation
LAYER1_THRESHOLD=$(awk "BEGIN {print $BASE * $LAYER1_THRESHOLD_MULT}")
```

**Testing workflow:**
```bash
# Test main script
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | src/statusline.sh

# Test utility functions
source src/statusline-utils.sh
get_daily_cost "2025-10-08T15:00:00-07:00"

# Test calibration tool
tools/calibrate_weekly_usage.sh 18.5
```

**File organization:**
- `src/statusline.sh` - Main script (keep clean, delegate to utilities)
- `src/statusline-*.sh` - Utility modules (self-contained, reusable functions)
- `tools/` - Standalone tools (calibration, maintenance)
- `config/` - User config (gitignored) + example template

### Contributing

1. Fork the repository
2. Create a feature branch
3. Follow development principles in CLAUDE.md
4. Test thoroughly with your plan (pro/max5x/max20x)
5. Submit pull request with clear description

**Development repository:** `git@github.com:hell0github/claude-statusline-dev.git`

## Acknowledgments

- Plugin for [Claude Code](https://claude.com/claude-code)
- Uses [ccusage](https://www.npmjs.com/package/ccusage) for usage tracking
- Inspired by [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
- Thanks to the community for better usage awareness in AI-assisted coding

---

**Note:** This is an unofficial third-party tool and is not affiliated with or endorsed by Anthropic.
