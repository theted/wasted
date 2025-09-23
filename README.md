# Wasted
Track time spent waiting for commands to finish and summarize it over time.

Commands:
- `wasted`: runs a command, measures wall time, and appends an entry to `~/.wasted.json`.
- `wasted-total`: prints the total time wasted, number of operations, and the span in days.
- `wasted-stats`: analyzes the log to surface bottlenecks (top commands, families, weeks, etc.).
- `wasted-debug`: prints the contents of `~/.wasted.json`.

Requirements:
- `bash`, `date` (GNU), and `jq` installed and on `PATH`.

## Usage

Examples:

```
wasted docker-compose up -d
wasted sleep 5
wasted ping -c 3 google.com
```

Example log file (`~/.wasted.json`):
```
[
  {
    "datetime": "2023-10-27T10:30:00Z",
    "time_spent_seconds": 5.0,
    "command": "sleep 5",
    "cwd": "/home/alice/project-a"
  },
  {
    "datetime": "2023-10-27T10:30:10Z",
    "time_spent_seconds": 3.3,
    "command": "ping -c 3 google.com",
    "cwd": "/home/alice/project-a"
  },
  {
    "datetime": "2023-10-27T10:30:25Z",
    "time_spent_seconds": 12.5,
    "command": "docker-compose up -d",
    "cwd": "/home/alice/project-b"
  }
]
```

Summarize totals:

```
wasted-total
# 1 hour, 51 minutes, 51 seconds wasted in 11 commands in 5 days.

# short/compact format
wasted-total --short
# 6711s wasted in 11 commands in 5 days.
```

## Installation (Linux)

You can link these scripts into a directory on your `PATH`.

Option A — user-local install (recommended):

```
# ensure ~/.local/bin is on your PATH
mkdir -p ~/.local/bin
ln -s "$(pwd)/wasted.sh" ~/.local/bin/wasted
ln -s "$(pwd)/wasted-total.sh" ~/.local/bin/wasted-total
ln -s "$(pwd)/wasted-stats.sh" ~/.local/bin/wasted-stats
ln -s "$(pwd)/wasted-debug.sh" ~/.local/bin/wasted-debug
```

Add to your shell profile if needed (bash example):

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Option B — system-wide (requires sudo):

```
sudo ln -s "$(pwd)/wasted.sh" /usr/local/bin/wasted
sudo ln -s "$(pwd)/wasted-total.sh" /usr/local/bin/wasted-total
sudo ln -s "$(pwd)/wasted-stats.sh" /usr/local/bin/wasted-stats
sudo ln -s "$(pwd)/wasted-debug.sh" /usr/local/bin/wasted-debug
```

Then run:

```
wasted sleep 1
wasted-total
wasted-debug
```

## Notes
- Log is stored at `~/.wasted.json`.
- `wasted` returns the wrapped command’s exit code.
- Remove `~/.wasted.json` to reset history.
- Requires GNU `date` for `wasted-total` (standard on most Linux distros).

## Installation (macOS)

Requirements:
- jq: `brew install jq`
- (Recommended) GNU coreutils for `gdate`: `brew install coreutils`

Link the scripts (user-local example):

```
mkdir -p ~/bin
ln -s "$(pwd)/wasted.sh" ~/bin/wasted
ln -s "$(pwd)/wasted-total.sh" ~/bin/wasted-total
ln -s "$(pwd)/wasted-stats.sh" ~/bin/wasted-stats
ln -s "$(pwd)/wasted-debug.sh" ~/bin/wasted-debug
```

Ensure `~/bin` is on your PATH (zsh default on macOS):

```
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Notes for macOS:
- `wasted-total` and `wasted-stats` auto-detect `gdate` when available (via Homebrew coreutils) and fall back to BSD `date` parsing.
- `wasted` works with the system `date` and does not require `gdate`.

## Statistics

Use `wasted-stats` to explore where your time goes and spot bottlenecks:

Examples:

```
wasted-stats             # top commands, top waits, weekly totals
wasted-stats --family    # include top families (docker, git, node-pm, ...)
wasted-stats --paths     # include top paths (cwd)
wasted-stats --threshold 120  # alert for waits >= 120s
wasted-stats --no-threshold   # disable threshold alerts
wasted-stats --top 15    # show more top commands
wasted-stats --weeks     # weekly totals only
wasted-stats --days      # daily totals only
```

What you get:
- Top commands: aggregated by the base command (first word), with seconds and percentage of the total.
- Top families (optional with `--family`): groups related commands (e.g., docker build/pull/compose) for broader insights.
- Top paths (optional with `--paths`): aggregate by the directory where commands were run to spot slow projects/dirs.
- Top waits: the five longest single operations.
- Threshold alerts (configurable with `--threshold`): list waits exceeding a given time.
- Weekly totals: ISO week bucketed sums to see trends.

Ideas for further analysis:
- Hour-of-day heatmap to see when slowdowns occur.
- Per-branch or per-repo breakdowns by parsing CWD/environment.
