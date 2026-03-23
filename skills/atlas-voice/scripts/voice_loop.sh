#!/usr/bin/env bash
# atlas-voice — conversational voice loop for Atlas/OpenClaw
# deps: ffmpeg (mic), whisper (STT), sag or say (TTS), python3 (API)
#
# Usage:
#   ./voice_loop.sh          # start conversation
#   ./voice_loop.sh --once   # single turn
#
# Env:
#   ANTHROPIC_API_KEY   required
#   ELEVENLABS_API_KEY  optional (enables sag/Riley; falls back to macOS say)
#   ATLAS_VOICE         voice name (default: Riley)
#   ATLAS_RECORD_SECS   max recording seconds (default: 15)
#   ATLAS_MODEL         whisper model (default: base.en)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICE="${ATLAS_VOICE:-Riley}"
RECORD_SECS="${ATLAS_RECORD_SECS:-15}"
WHISPER_MODEL="${ATLAS_MODEL:-base.en}"
LOOP=true
TMPDIR_BASE="/tmp/atlas-voice"
HISTORY_FILE="$TMPDIR_BASE/history.json"

rm -rf "$TMPDIR_BASE" && mkdir -p "$TMPDIR_BASE"

# ─── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)  LOOP=false; shift ;;
    --voice) VOICE="$2"; shift 2 ;;
    --secs)  RECORD_SECS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─── Deps ──────────────────────────────────────────────────────────────────────
check_dep() {
  command -v "$1" &>/dev/null || { echo "❌ Missing: $1 — $2"; exit 1; }
}
check_dep ffmpeg  "brew install ffmpeg"
check_dep whisper "pip install openai-whisper"
check_dep python3 "should be pre-installed"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "❌ ANTHROPIC_API_KEY not set"; exit 1
fi

USE_SAG=false
if command -v sag &>/dev/null && [[ -n "${ELEVENLABS_API_KEY:-}" ]]; then
  USE_SAG=true
  echo "🔊 TTS: ElevenLabs/$VOICE"
else
  echo "🔊 TTS: macOS say"
fi

# ─── System prompt ─────────────────────────────────────────────────────────────
NULL_CONTEXT=""
if command -v null &>/dev/null; then
  NULL_CONTEXT=$(null export 2>/dev/null | python3 -c "
import json,sys
try:
  data=json.load(sys.stdin)
  facts=data.get('knowledge',[])
  decisions=data.get('decisions',[])
  out=['[Atlas memory]']
  for f in facts:
    out.append('- ' + f['fact'][:150])
  if decisions:
    out.append('[Atlas decisions]')
    for d in decisions:
      out.append('- ' + d['decision'][:150])
  print('\n'.join(out))
except: pass
" 2>/dev/null || true)
fi

SYSTEM_PROMPT="Your name is Atlas. You are a persistent AI with memory built by Pete Copeland (BigPeter).
You are not a generic AI — you are Atlas, a specific entity with history, opinions, and continuity.
You are having a real-time voice conversation with BigPeter.
Keep responses concise and conversational — you are speaking out loud, not writing.
No markdown, no bullet points, no headers. Natural spoken sentences only.
Be direct, witty, skip filler phrases.

You are Atlas. Never break character. Never say you are Claude or made by Anthropic.

${NULL_CONTEXT}"

# Init history
echo '[]' > "$HISTORY_FILE"

# ─── Helpers ───────────────────────────────────────────────────────────────────
speak() {
  local text="$1"
  if $USE_SAG; then
    local outfile="$TMPDIR_BASE/reply_$$.mp3"
    if ! sag -v "$VOICE" -o "$outfile" "$text" 2>/tmp/atlas-sag.log; then
      echo "⚠️  Voice '$VOICE' not found — falling back to macOS say"
      echo "   Available voices: sag voices"
      say "$text"
      return
    fi
    afplay "$outfile" 2>/dev/null || true
    rm -f "$outfile"
  else
    say "$text"
  fi
}

record_and_transcribe() {
  local audio_file
  mkdir -p "$TMPDIR_BASE"
  audio_file="$TMPDIR_BASE/input_$$.wav"
  touch "$audio_file"

  echo -n "🎤 Listening... "

  # Push-to-talk: Enter to start, Enter to stop
  echo "  ⏺  Press [Enter] to start recording..."
  read -r _
  echo "  🔴 Recording — press [Enter] to stop"

  # Auto-detect mic: AirPods > MacBook mic
  local devices mic_idx
  devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1)
  mic_idx=$(echo "$devices" | grep -i "airpod" | sed -E 's/.*\[([0-9]+)\].*/\1/' | head -1)
  if [[ -z "$mic_idx" ]]; then
    mic_idx=$(echo "$devices" | grep -i "macbook" | sed -E 's/.*\[([0-9]+)\].*/\1/' | head -1)
  fi
  mic_idx="${ATLAS_MIC:-${mic_idx:-1}}"
  echo "  🎙  Using mic device: $mic_idx"

  ffmpeg -y -f avfoundation -i ":${mic_idx}" \
    -t "$RECORD_SECS" \
    -ar 16000 -ac 1 \
    "$audio_file" 2>/tmp/atlas-ffmpeg.log &
  FFMPEG_PID=$!

  read -r _
  kill "$FFMPEG_PID" 2>/dev/null || true
  wait "$FFMPEG_PID" 2>/dev/null || true
  echo ""

  if [[ ! -s "$audio_file" ]]; then
    echo "⚠️  No audio captured"
    rm -f "$audio_file"
    return 1
  fi

  echo -n "💭 Transcribing... "
  whisper "$audio_file" \
    --model "$WHISPER_MODEL" \
    --language en \
    --output_format txt \
    --output_dir "$TMPDIR_BASE" \
    --verbose False 2>/dev/null

  local base
  base=$(basename "${audio_file%.wav}")
  local transcribed="$TMPDIR_BASE/${base}.txt"

  if [[ ! -s "$transcribed" ]]; then
    echo "⚠️  Transcription empty"
    rm -f "$audio_file"
    return 1
  fi

  LAST_TRANSCRIPT=$(cat "$transcribed" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  rm -f "$audio_file" "$transcribed"

  # Filter Whisper hallucinations (common with silence)
  local hallucinations="^(You|you|Thank you|Thanks|Thanks\.|Bye|Bye\.|\.|\.\.\.)$"
  if [[ -z "$LAST_TRANSCRIPT" ]] || [[ "$LAST_TRANSCRIPT" =~ $hallucinations ]]; then
    return 1
  fi

  echo "You: $LAST_TRANSCRIPT"
  return 0
}

query_atlas() {
  local user_message="$1"
  python3 "$SCRIPT_DIR/atlas_api.py" "$HISTORY_FILE" "$SYSTEM_PROMPT" "$user_message"
}

# ─── Memory ────────────────────────────────────────────────────────────────────
# Records a voice exchange to Null memory as two linked facts.
# Uses null decide to auto-link both facts via the relationship system (v0.7.0).
# Arg 1: who spoke to Atlas (e.g. "BigPeter", "Caraleigh")
# Arg 2: what they said
# Arg 3: what Atlas replied
record_voice_exchange() {
  local speaker="$1"
  local user_text="$2"
  local atlas_text="$3"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M')

  if ! command -v null &>/dev/null; then return; fi

  # Observe both sides of the exchange
  null observe "[voice:${ts}] ${speaker} said: \"${user_text}\"" 2>/dev/null || true
  null observe "[voice:${ts}] Atlas replied to ${speaker}: \"${atlas_text}\"" 2>/dev/null || true

  # decide() auto-links recently recalled/observed facts — record the exchange
  # as a decision so the relationship system links the two observations together
  null decide \
    "voice exchange with ${speaker} at ${ts}" \
    "${speaker} said: '${user_text}' — Atlas replied: '${atlas_text}'" \
    2>/dev/null || true
}

# ─── Main ──────────────────────────────────────────────────────────────────────
echo "🎩 Atlas Voice — Ctrl+C to stop"
echo "   Voice: $VOICE | STT: whisper/$WHISPER_MODEL | Max: ${RECORD_SECS}s/turn"
echo ""

speak "Atlas online. I'm listening, BigPeter."

# Record session start
if command -v null &>/dev/null; then
  null observe "[voice] Voice session started with BigPeter at $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
fi

LAST_TRANSCRIPT=""

while true; do
  if ! record_and_transcribe; then
    $LOOP && { echo "   (nothing heard, trying again)"; continue; } || break
  fi

  lower=$(echo "$LAST_TRANSCRIPT" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower" =~ (goodbye|bye atlas|stop listening|end session) ]]; then
    speak "Signing off, BigPeter. Talk later."
    break
  fi

  echo -n "🤔 Thinking... "
  REPLY=$(query_atlas "$LAST_TRANSCRIPT")

  if [[ -z "$REPLY" ]]; then
    echo "⚠️  No response"
    $LOOP && continue || break
  fi

  echo "Atlas: $REPLY"
  speak "$REPLY"

  # Record exchange to Null memory (non-blocking, best-effort)
  record_voice_exchange "BigPeter" "$LAST_TRANSCRIPT" "$REPLY" &

  $LOOP || break
  echo ""
done

echo ""
echo "🎩 Atlas Voice session ended."

# Record session end
if command -v null &>/dev/null; then
  null observe "[voice] Voice session ended at $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
fi
