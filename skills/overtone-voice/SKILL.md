---
name: overtone-voice
description: Speak text aloud on this Mac through Overtone, a local on-device text-to-speech app. Use when the user asks for a spoken or voice answer, wants something read aloud, or wants to be told by voice when a long task finishes.
user-invocable: true
---

# Speaking through Overtone

Overtone is a menu bar app on this Mac that synthesizes speech locally and plays it on
the speakers. It exposes a loopback-only HTTP API on port 7789. Nothing leaves the
machine and no API key is involved.

## Check that it is available

```bash
curl -s -m 1 http://127.0.0.1:7789/health
```

`{"status":"ok"}` means Overtone is running. Anything else — connection refused, a
timeout — means it is not; say so in text instead of retrying in a loop.

`GET /skill` returns this document, so you can always re-read the current contract
from the app itself.

## Speak

```bash
curl -sS -X POST http://127.0.0.1:7789/speak \
  -H 'content-type: application/json' \
  -d '{"text":"Сборка прошла, тесты зелёные."}'
```

The call returns `{"status":"speaking"}` immediately and audio plays in the background.
A new `/speak` replaces whatever is currently playing.

Optional fields, all falling back to the app's current settings:

| Field | Values |
| --- | --- |
| `voice` | `M1`–`M5`, `F1`–`F5` |
| `language` | `ru`, `en`, `uk`, `de`, `fr`, `es`, `it`, `pt`, `pl`, `ja`, `ko` |
| `speed` | `0.7`–`2.0`, default `1.05` |
| `total_step` | `5` fast, `8` balanced, `10` best |

Always pass `language` when the text is not in the user's usual language — the voice
reads Russian text with an English `language` badly.

## Control what is playing

| Request | Effect |
| --- | --- |
| `POST /stop` | stop generation and playback |
| `POST /pause` | toggle pause, answers with `paused` or `playing` |
| `GET /status` | `idle` / `speaking` / `paused`, plus `elapsed` and `buffered` seconds |

To wait until the speech has finished before moving on:

```bash
while [ "$(curl -s http://127.0.0.1:7789/status | grep -o '"status":"[a-z]*"')" != '"status":"idle"' ]; do
  sleep 1
done
```

## Writing text that sounds good

- Write sentences, with punctuation. Sentence ends are where the voice breathes.
- Say numbers and units the way a person would: "три с половиной секунды", not "3.5s".
- Leave out code, paths, URLs, tables and markdown. If you must refer to a file, say
  its name, not its full path.
- Keep it to what someone would want to hear — two or three sentences for a status
  update. Put the detail in your text answer instead.
- Do not read out an entire diff or log. Summarize, then offer the details in text.

## When to use it

Speak when the user asked to hear something, or when they asked to be notified by
voice about a long-running task. Do not narrate every step by default — an unexpected
voice from the speakers is startling. Text stays the primary channel; speech is an
addition to it, never a replacement.
