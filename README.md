# Wasted

![xkcd: Compiling](https://imgs.xkcd.com/comics/compiling.png)

_...but where did that time go?_

Track time spent waiting for commands to finish and summarize it over time.

Commands:
- `wasted`: runs a command, measures wall time, and appends an entry to `~/.wasted.json`. When run with no arguments, it prints statistics (top commands, paths, waits, weekly totals, latest, and a total summary).

Requirements:
- `bash`, `date`, and `jq` on `PATH`. On Linux, `date` is GNU `date`; on macOS, BSD `date` works and `gdate` (GNU coreutils) is recommended for consistent stats.

## Usage

Examples:

```
wasted docker-compose up -d
wasted sleep 5
wasted ping -c 3 google.com
```

Totals summary:

```
wasted
# ... tables ...
# 1 hour 51 minutes 51 seconds wasted waiting on 11 commands during 5 days.
```

## Installation (Linux)

You can link these scripts into a directory on your `PATH`.

Option A — user-local install (recommended):

```
# ensure ~/.local/bin is on your PATH
mkdir -p ~/.local/bin
ln -s "$(pwd)/wasted.sh" ~/.local/bin/wasted
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
sudo ln -s "$(pwd)/wasted-debug.sh" /usr/local/bin/wasted-debug
```

Then run:

```
wasted sleep 1
wasted
wasted-debug
```

## Notes
- Log is stored at `~/.wasted.json`.
- `wasted` returns the wrapped command’s exit code.
- Remove `~/.wasted.json` to reset history.
- Requires GNU `date` (or `gdate` on macOS) for some date calculations used in stats.
- The total summary day count reflects unique weekdays (Mon–Fri) that have at least one command; weekends are excluded.

## Installation (macOS)

Requirements:
- jq: `brew install jq`
- (Recommended) GNU coreutils for `gdate`: `brew install coreutils`

Link the scripts (user-local example):

```
mkdir -p ~/bin
ln -s "$(pwd)/wasted.sh" ~/bin/wasted
ln -s "$(pwd)/wasted-debug.sh" ~/bin/wasted-debug
```

Ensure `~/bin` is on your PATH (zsh default on macOS):

```
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Notes for macOS:
- `wasted` auto-detects `gdate` when available (via Homebrew coreutils) and falls back to BSD `date` parsing for stats.
- `wasted` works with the system `date` to record commands and does not require `gdate`.

## Statistics

Run `wasted` with no arguments to explore where your time goes and spot bottlenecks:

```
wasted                   # top commands, top paths, top waits, weekly totals, latest 5, total summary
```

What you get:
- Top commands: aggregated by the base command (first word), with seconds, number of commands, and percentage of the total. Title includes total command count.
- Top paths: aggregate by the directory where commands were run to spot slow projects/dirs.
- Top waits: the five longest single operations.
- Latest 10 >60s: most recent commands that took more than 60 seconds.
- Weekly totals: ISO week bucketed sums to see trends.
- Latest 5 commands: most recent entries with date, command, seconds, and path.
