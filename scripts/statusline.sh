#!/bin/bash
# Claude Gauge statusline — shows rate limits + writes cache for menu bar
input=$(cat)

# Write cache for menu bar app
mkdir -p ~/.claude-gauge
echo "$input" | jq '{rate_limits: .rate_limits, cost: .cost, model: .model, context_window: .context_window}' > ~/.claude-gauge/data.json 2>/dev/null

# Build bar: $1=percentage $2=width
bar() {
  local pct=$1 w=${2:-8}
  local filled=$(( (pct * w + 50) / 100 ))
  local empty=$((w - filled))
  local b=""
  for ((i=0; i<filled; i++)); do b+="▰"; done
  for ((i=0; i<empty; i++)); do b+="▱"; done
  echo "$b"
}

# Time left: $1=resets_at (unix timestamp)
timeleft() {
  local resets=$1
  local now=$(date +%s)
  local delta=$((resets - now))
  [ "$delta" -le 0 ] && return
  local h=$((delta / 3600))
  local m=$(( (delta % 3600) / 60 ))
  if [ "$h" -ge 24 ]; then
    local d=$((h / 24))
    h=$((h % 24))
    echo "${d}d·${h}h"
  elif [ "$h" -gt 0 ]; then
    echo "${h}h·${m}m"
  else
    echo "${m}m"
  fi
}

# Extract data with jq
pct5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
rst5=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
pct7=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
rst7=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

parts=""

if [ -n "$pct5" ]; then
  pct5=${pct5%.*}
  tl=""
  [ -n "$rst5" ] && tl=$(timeleft "$rst5") && [ -n "$tl" ] && tl=" $tl"
  parts="◷ $(bar "$pct5") ${pct5}%${tl}"
fi

if [ -n "$pct7" ]; then
  pct7=${pct7%.*}
  tl=""
  [ -n "$rst7" ] && tl=$(timeleft "$rst7") && [ -n "$tl" ] && tl=" $tl"
  [ -n "$parts" ] && parts="$parts  "
  parts="${parts}◫ $(bar "$pct7") ${pct7}%${tl}"
fi

echo "$parts"
