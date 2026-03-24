---
name: atlas-voice
description: "Real-time voice conversation with Atlas — speak and hear responses. Loops mic recording → Whisper STT → OpenClaw agent → ElevenLabs TTS. Use when: user asks to 'talk to Atlas', 'start a voice session', 'use voice mode', or wants to have a spoken conversation. Requires sag (ElevenLabs TTS), whisper (STT), and ffmpeg (mic). macOS only for mic capture."
metadata:
  {
    "openclaw":
      {
        "emoji": "🎙️",
        "os": ["darwin"],
        "requires": { "bins": ["ffmpeg", "whisper"] },
        "install":
          [
            {
              "id": "sag",
              "kind": "brew",
              "formula": "steipete/tap/sag",
              "bins": ["sag"],
              "label": "Install sag (ElevenLabs TTS)",
            },
          ],
      },
  }
---

# Atlas Voice

Conversational voice loop: mic → Whisper STT → OpenClaw agent → sag TTS → repeat.

## Quick Start

```bash
# Start a voice conversation
bash ~/.openclaw/skills/atlas-voice/scripts/voice_loop.sh

# Single turn only
bash ~/.openclaw/skills/atlas-voice/scripts/voice_loop.sh --once

# Resume a session
bash ~/.openclaw/skills/atlas-voice/scripts/voice_loop.sh --session <session-id>
```

## Setup

1. **Install sag** (ElevenLabs TTS):

   ```bash
   brew install steipete/tap/sag
   ```

2. **Set ElevenLabs API key:**

   ```bash
   openclaw config set ELEVENLABS_API_KEY sk-...
   # or export ELEVENLABS_API_KEY=sk-... in your shell
   ```

3. **Whisper already installed** via brew. First run downloads the model (~75MB for base.en).

4. **Grant mic access** to Terminal/iTerm when prompted on first run.

## Configuration

| Env var             | Default   | Description                                          |
| ------------------- | --------- | ---------------------------------------------------- |
| `ATLAS_VOICE`       | `Atlas`   | sag voice name or ElevenLabs voice ID                |
| `ATLAS_RECORD_SECS` | `15`      | Max seconds to record per turn                       |
| `ATLAS_MODEL`       | `base.en` | Whisper model (base.en = fast, medium.en = accurate) |
| `ATLAS_SESSION_ID`  | —         | Pin to an existing OpenClaw session                  |

## Choosing a Voice

```bash
sag voices          # list all available voices
sag -v "Adam" "test"  # try a voice before setting it
```

For Atlas, something with gravitas works well — "Adam", "Daniel", or a custom cloned voice. Set permanently:

```bash
export ATLAS_VOICE="Adam"
```

Or save in `~/.zshrc` / `~/.bashrc`.

## How It Works

1. **Record** — ffmpeg captures mic via AVFoundation, stops on 1.5s of silence or timeout
2. **Transcribe** — Whisper converts audio → text locally (no API, no cost)
3. **Think** — `openclaw agent` sends text to your running OpenClaw instance
4. **Speak** — sag synthesizes the reply via ElevenLabs and plays via `afplay`
5. **Remember** — both sides of each exchange are written to Null memory (if installed)
6. **Loop** — back to step 1

Session ID is preserved across turns for conversation continuity.

## Voice Memory

Each exchange is automatically recorded to Null with two linked facts:

- `[voice] BigPeter said: "..."`
- `[voice] Atlas replied to BigPeter: "..."`

Both facts are linked via Null's relationship system so recalling one surfaces the other. Session start/end events are also recorded.

To recall voice conversations later:

```bash
null recall "voice caraleigh"
null recall "voice what did I say about"
```

If someone other than BigPeter is present, the speaker name in the facts will reflect who was in the conversation (currently hardcoded to BigPeter — future `--people` flag planned).

## Troubleshooting

**No mic input / ffmpeg error:**

```bash
# List audio devices
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -i "audio"
# If mic isn't device :0, set explicitly:
# Edit voice_loop.sh line: -i ":0" → -i ":<device_number>"
```

**Whisper too slow:**

- Use `ATLAS_MODEL=tiny.en` for fastest response (~40MB model)
- Use `ATLAS_MODEL=small.en` for better accuracy with reasonable speed

**sag voice not found:**

```bash
sag voices  # find the exact name
export ATLAS_VOICE="<exact-name-from-list>"
```

**OpenClaw agent not responding:**

```bash
openclaw gateway status  # ensure gateway is running
openclaw gateway start   # start if needed
```
