#!/bin/bash
# Claude Gauge statusline — shows rate limits + writes cache for menu bar
input=$(cat)

# Data dir: plugin data dir if installed as plugin, otherwise ~/.claude-gauge
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude-gauge}"
mkdir -p "$DATA_DIR"

# Write cache for menu bar app
echo "$input" | jq '{rate_limits: .rate_limits, cost: .cost, model: .model, context_window: .context_window}' > "$DATA_DIR/data.json" 2>/dev/null

# Read config
# - show: array of sections to display, in order (default: ["context", "session", "week"])
# - tokens: show token counts next to context (default: true)
# - style: bar style (default: "blocks") — blocks, classic, dots, thin, ascii
# - icons: icon set (default: "default") — default, emoji, clocks, letters, minimal, ascii, nerd, none
CFG="$DATA_DIR/config.json"
cfg_order=$(jq -r '(.show // ["context","session","week"]) | join(" ")' "$CFG" 2>/dev/null) || cfg_order="context session week"
show_tokens=$(jq -r 'if .tokens == null then true else .tokens end' "$CFG" 2>/dev/null) || show_tokens="true"
style=$(jq -r '.style // "blocks"' "$CFG" 2>/dev/null) || style="blocks"
icons=$(jq -r '.icons // "default"' "$CFG" 2>/dev/null) || icons="default"

# Bar styles: filled/empty characters
case "$style" in
  classic)  FILL="█" EMPTY="░" ;;
  dots)     FILL="●" EMPTY="○" ;;
  thin)     FILL="━" EMPTY="─" ;;
  ascii)    FILL="#" EMPTY="·" ;;
  arrows)   FILL="▸" EMPTY="▹" ;;
  *)        FILL="▰" EMPTY="▱" ;;  # blocks (default)
esac

# Icon sets: context, session, week
case "$icons" in
  emoji)    IC="🧠" IS="⏱" IW="📅" ;;
  clocks)   IC="◔" IS="◑" IW="◕" ;;
  letters)  IC="C" IS="S" IW="W" ;;
  minimal)  IC="·" IS="·" IW="·" ;;
  ascii)    IC="[c]" IS="[s]" IW="[w]" ;;
  nerd)     IC="" IS="" IW="" ;;
  none)     IC="" IS="" IW="" ;;
  *)        IC="◧" IS="◷" IW="◫" ;;  # default
esac

# Build bar: $1=percentage $2=width
bar() {
  local pct=$1 w=${2:-8}
  local filled=$(( (pct * w + 50) / 100 ))
  local empty=$((w - filled))
  local b=""
  for ((i=0; i<filled; i++)); do b+="$FILL"; done
  for ((i=0; i<empty; i++)); do b+="$EMPTY"; done
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

# Format tokens: 1234567 → 1.2M, 12345 → 12K
fmttok() {
  local t=$1
  if [ "$t" -ge 1000000 ]; then
    local r=$((t % 1000000))
    if [ "$r" -lt 100000 ]; then
      echo "$((t / 1000000))M"
    else
      local m=$((t / 100000))
      echo "$((m / 10)).$((m % 10))M"
    fi
  elif [ "$t" -ge 1000 ]; then
    echo "$((t / 1000))K"
  else
    echo "$t"
  fi
}

# Extract data with jq
pct5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
rst5=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
pct7=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
rst7=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
pctc=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
ctxsize=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
ctxused=$(echo "$input" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)' 2>/dev/null)

# Build output in configured order
parts=""
for section in $cfg_order; do
  segment=""
  case "$section" in
    session)
      if [ -n "$pct5" ]; then
        p=${pct5%.*}
        tl=""
        [ -n "$rst5" ] && tl=$(timeleft "$rst5") && [ -n "$tl" ] && tl=" $tl"
        segment="${IS:+$IS }$(bar "$p") ${p}%${tl}"
      fi
      ;;
    week)
      if [ -n "$pct7" ]; then
        p=${pct7%.*}
        tl=""
        [ -n "$rst7" ] && tl=$(timeleft "$rst7") && [ -n "$tl" ] && tl=" $tl"
        segment="${IW:+$IW }$(bar "$p") ${p}%${tl}"
      fi
      ;;
    context)
      if [ -n "$pctc" ]; then
        p=${pctc%.*}
        tokens=""
        if [ "$show_tokens" = "true" ] && [ -n "$ctxsize" ] && [ "$ctxsize" -gt 0 ] && [ -n "$ctxused" ]; then
          tokens=" $(fmttok "$ctxused")/$(fmttok "$ctxsize")"
        fi
        segment="${IC:+$IC }$(bar "$p") ${p}%${tokens}"
      fi
      ;;
  esac
  if [ -n "$segment" ]; then
    [ -n "$parts" ] && parts="$parts  "
    parts="${parts}${segment}"
  fi
done

echo "$parts"
