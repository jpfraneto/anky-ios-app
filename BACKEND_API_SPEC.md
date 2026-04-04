# Backend Evolution: Adding the Conversation Layer

## What exists today

The iOS app talks to `https://anky.app/swift/v2`. Current endpoints:

| Endpoint | What it does |
|---|---|
| `POST /write` | Submit writing session → `MobileWriteResponse` (outcome, flowScore, persisted, spawned artifacts) |
| `GET /writings` | Full writing history → `[WritingItem]` |
| `GET /writing/:sessionId/status` | Poll for artifact generation status |
| `POST /auth/challenge` + `/auth/verify` | Seed-based wallet auth |
| `GET /me` | User profile |
| `GET /settings`, `PATCH /settings` | User preferences |
| `GET /cuentacuentos/*` | Story system |
| `POST /devices` | Push notification registration |

Honcho holds user memory from all past interactions. But **nothing uses it to talk back to the user**. The app hardcodes Anky's responses after writing sessions.

## What's missing

Two things. Both build on what's already there.

---

### 1. `POST /write` needs to return Anky's response

The endpoint already exists and already returns `MobileWriteResponse`. **Evolve it.** Add a `response` field that contains Anky's actual words — generated using the writing content + Honcho memory.

#### Current response shape:
```json
{
  "ok": true,
  "sessionId": "uuid",
  "outcome": "anky",
  "wordCount": 487,
  "durationSeconds": 342.5,
  "flowScore": 0.72,
  "persisted": true,
  "spawned": { "ankyId": "...", "cuentacuentos": true },
  "walletAddress": "0x...",
  "statusUrl": "/writing/uuid/status"
}
```

#### Add these fields:
```json
{
  "...existing fields...",

  "ankyResponse": "you stayed with it.\ni can feel what moved through you.\nthe part about your father — that thread has been pulling at you for three sessions now.",
  "nextPrompt": "what would you say to him if he could hear you?",
  "mood": "reflective"
}
```

**`ankyResponse`** — Anky's reply to this specific writing session. Generated from:
1. The writing text just submitted
2. Honcho memory of all previous sessions
3. Patterns: recurring themes, emotional arcs, unfinished threads

Rules for the response:
- Lowercase always
- Short lines, line breaks between thoughts
- Must reference something specific from the writing (not generic encouragement)
- If the writing qualifies for anky (8+ min): acknowledge the achievement without being cheesy
- If short session: be gentle, don't make them feel like they failed
- If Honcho reveals a pattern across sessions: name it ("you keep circling back to this")

**`nextPrompt`** — Optional. Anky's next question/invitation for the user's next session. One sentence, max 10 words. This becomes the first message the user sees next time they open the app.

**`mood`** — Helps frontend set visual tone. One of: `reflective`, `celebratory`, `gentle`, `curious`, `deep`. Frontend doesn't use this yet but will.

If response generation takes time (LLM call), two options:
- **Option A**: Return `ankyResponse: null` immediately, then push it via the existing `/writing/:sessionId/status` polling (add a `response` field to `WritingStatusResponse`)
- **Option B**: Hold the request until response is ready (the app already shows a typing indicator for 1.5s, can extend)

---

### 2. `GET /chat/prompt` — What should Anky say on app launch?

New endpoint. Called once per app session to get Anky's opening message.

#### Request
```
GET /swift/v2/chat/prompt
Authorization: Bearer <token>
```

#### Response
```json
{
  "ok": true,
  "text": "what did you leave unsaid yesterday?",
  "messageId": "uuid"
}
```

**Behavior:**
- First-ever user: return `"tell me who you are."`
- Returning user: use Honcho memory to generate a prompt that picks up where things left off
- One short sentence. A question or invitation. Never a command.
- Never repeat a prompt already given
- If the user wrote about something heavy last time, acknowledge it: "that was a lot. what's left?"
- If flow scores have been improving: "you're finding the rhythm."

---

## What the iOS app does with this

1. On app launch → `GET /chat/prompt` → display as Anky's first message (bright, current session)
2. All previous messages loaded from local persistence (dimmed, 0.35 opacity)
3. User writes → `POST /write` → get back `ankyResponse` + `nextPrompt`
4. Display `ankyResponse` as Anky's message in the chat
5. Store `nextPrompt` locally — use it as fallback if `/chat/prompt` fails next launch
6. Everything persisted to local JSON for offline/instant loading

## What does NOT need to change

- Auth flow — works fine
- `/writings` — keep for history/profile views
- `/writing/:sessionId/status` — keep for artifact polling
- Cuentacuentos, settings, devices — all fine
- Honcho storage — keep storing everything, just also read from it now

## The one thing that makes this work

Anky's response must prove it read the writing. Not "great job keeping going" but "the part where you described the kitchen — you've mentioned that room in three different sessions." That's what makes the user trust. That's what makes them come back.
