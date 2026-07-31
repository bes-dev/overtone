# Overtone

Local, on-device text to speech for macOS, in the menu bar.

Paste text, press ⌘↩, hear it. Nothing leaves the machine: the speech model, the
inference server and the voices all live inside the app bundle. No account, no API
key, no network.

- **Fast.** Generation runs at roughly 0.1× real time on Apple Silicon; audio starts
  in under half a second and playback never waits for the stream.
- **Natural.** The text is normalized and chunked on sentence boundaries, so it reads
  like prose rather than a list of words. [Why that matters.](#chunking-and-prosody)
- **Scriptable.** A loopback HTTP API on port 7789, plus a skill file that teaches a
  coding agent to answer out loud.
- **Ten voices, twelve languages**, adjustable speed, quality and volume.

## Install

Download `Overtone-1.0.0.dmg` from the [latest release][releases], open it and drag
Overtone to Applications.

The app is signed ad-hoc, not notarized, so Gatekeeper will refuse the first launch.
Either right-click the app and choose *Open*, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Overtone.app
```

macOS 14 or later, Apple Silicon.

[releases]: https://github.com/bes-dev/overtone/releases/latest

## Using it

The menu bar item opens a panel with the text to read, transport controls and a
progress bar. The `?` button opens a help page with every shortcut and the scripting
API; `esc` returns.

| Shortcut | Where | Action |
| --- | --- | --- |
| `⌥⌘S` | anywhere | speak whatever is on the clipboard |
| `⌥⌘.` | anywhere | stop |
| `⌘↩` | in the panel | speak the text |
| `⌘.` | in the panel | stop |

Voice, language, quality, speed and volume are saved as you change them. Only
**Static MLProgram** restarts the speech server; everything else applies to the next
utterance.

Shortcuts.app exposes *Speak with Overtone*, *Speak clipboard with Overtone* and
*Stop Overtone*. The `overtone://` URL scheme takes `text`, and optionally `voice`
and `language`:

```bash
open "overtone://speak?text=Привет&voice=F2&language=ru"
```

## Control API

Bound to the loopback interface only.

```bash
curl -X POST http://127.0.0.1:7789/speak \
  -H 'content-type: application/json' \
  -d '{"text":"Привет! Это локальная озвучка.","voice":"M1","language":"ru"}'
```

`voice`, `language`, `speed`, `total_step` and `max_chunk_length` are optional and
fall back to the current settings.

| Endpoint | Purpose |
| --- | --- |
| `POST /speak` | synthesize and play, returns immediately |
| `POST /stop` | stop generation and playback |
| `POST /pause` | toggle pause, answers with the new state |
| `GET /status` | `idle`/`speaking`/`paused`, server state, elapsed and buffered seconds |
| `GET /skill` | the agent contract, as markdown |
| `GET /health` | liveness |

```bash
curl http://127.0.0.1:7789/status
{"buffered":7.92,"elapsed":2.14,"error":null,"server":"ready","status":"speaking"}
```

The low-level streaming endpoint stays on `http://127.0.0.1:7788/v1/audio/speech`.

## Letting a coding agent speak

[`skills/overtone-voice/SKILL.md`](skills/overtone-voice/SKILL.md) is written for
coding assistants: when to speak, how to call the API, and how to phrase text that
sounds good out loud. The sparkles button in the panel copies it to the clipboard,
and the app serves the same file at `GET /skill`, so an agent can fetch its own
instructions. Install it as a personal Claude Code skill:

```bash
ln -s "$PWD/skills/overtone-voice" ~/.claude/skills/overtone-voice
```

The app bundles that file as a resource, so the document, the button, the endpoint
and the installed skill can never drift apart.

## Build from source

The repository carries the app; it does not carry the 400 MB of model weights and the
compiled speech server. Take those from a release build:

```bash
brew install xcodegen
cp -R /Applications/Overtone.app/Contents/Resources/Runtime ./Runtime

xcodegen generate
xcodebuild -project Overtone.xcodeproj -scheme Overtone -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - .build/Build/Products/Release/Overtone.app
```

`Runtime/` needs `supertonic-server` (built from the `rust-server` crate of the
[Supertonic][supertonic] repository), `onnx/` with the model files, and
`voice_styles/` with the voice JSONs.

Unit tests cover the pure logic — text normalization, silence trimming and the
control-server HTTP parser:

```bash
xcodebuild -project Overtone.xcodeproj -scheme Overtone -configuration Debug \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

To package a DMG the way releases are built:

```bash
./scripts/make-dmg.sh
```

[supertonic]: https://github.com/supertone-inc/supertonic

## Chunking and prosody

The speech server splits input into chunks and synthesizes each one as a separate
utterance, so every chunk boundary costs the trailing silence of one utterance plus
an inter-chunk pause. Small chunks therefore break a sentence into bursts of a few
words separated by roughly a second of dead air.

`max_chunk_length` is an upper bound, not a target: the splitter already breaks on
sentence boundaries. The default of 300 characters keeps one sentence per chunk for
ordinary text, and the app sends `silence_ms=0` so only the model's own sentence
pauses remain. Measured on a 372-character Russian paragraph (M1, 8 steps):

| max_chunk_length | chunks | audio | wall | pauses at boundaries |
| --- | --- | --- | --- | --- |
| 32 | 26 | 39.5 s | 7.9 s | 25 × ~0.75 s, mid-sentence |
| 150 | 6 | 29.1 s | 3.1 s | 5 × ~1.15 s |
| 300 | 4 | 28.2 s | 2.6 s | 3 × ~1.1 s, sentence ends only |

Raising the limit past ~300 changes nothing but delays the first chunk, since time to
first audio depends on the first chunk alone.

The player also drops the half second of silence every utterance starts with, keeping
20 ms of preroll — that is where the rest of the startup latency went.

Input is normalized before synthesis: markdown emphasis and links, list bullets and
headings are removed, URLs are read as their host, and a hard-wrapped paragraph is
rejoined into one sentence while a heading or list item is terminated as its own.
Without that, wrapped text inherits the same chopped-up prosody as over-small chunks.

## How the pieces fit

| File | Responsibility |
| --- | --- |
| `AppState` | settings, speech lifecycle, wiring |
| `BackendController` | spawns, supervises and reclaims the speech server process |
| `StreamingSpeechRequest` | one streaming HTTP request to the server |
| `PCMStreamPlayer` | playback, lead-silence trimming, pause, device-change recovery |
| `SilenceTrim` / `SpeechText` | pure logic, unit tested |
| `ControlServer` / `ControlAPI` | loopback HTTP framing / routing onto the app |
| `GlobalHotKeys` | Carbon hotkey registration |
| `HelpView` / `AgentSkill` | the in-panel help page / the bundled SKILL.md |

If the app is force-killed, its speech server keeps the port; the next launch adopts
that healthy server instead of loading the model again. Restarting the server from the
UI terminates it first, but only after confirming the process really is this bundle's
binary. A second copy of the app notices the first one on the control port and quits
rather than fighting over the menu bar and the hotkeys.

## Credits and license

Speech comes from [Supertonic][supertonic] by Supertone Inc. — sample code under the
MIT License, model weights under the [OpenRAIL-M License][rail]. The release DMG
redistributes both; `MODEL_LICENSE` travels inside the app bundle, and the OpenRAIL-M
use-based restrictions apply to the model and to its output.

This app is MIT licensed — see [LICENSE](LICENSE).

[rail]: https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE
