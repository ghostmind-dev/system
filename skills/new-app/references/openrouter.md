# OpenRouter: AI on the person's own key

Every AI feature in a product runs on the OpenRouter account the person connects. We don't pay for inference, and
someone who wants a heavier experience pays for their own. This guide is the whole block: connecting the key, offering
models, calling them, and what to do when a model goes away. Reference implementation: Potion
(`shared/server/ai-models.ts`, `agent/ai-connection.ts`, `agent/ai-models.ts`).

## 1. Connect the key

- The person connects through **OpenRouter's PKCE flow**: send them to `https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256`,
  then exchange the code for a key that belongs to them. There is no client id or secret on our side.
- Store the key **AES-GCM-encrypted** in an `ai_connections` table that no user role can read; only a server decrypts it,
  at the moment it calls a model. The browser and the phone learn that a connection exists and its last four characters.
- **Never fall back to the owner's key.** Without a connection, AI features stay off and say "Connect your OpenRouter
  account in Settings → AI".
- References: `/Volumes/Projects/format` (`ai_connections`), `potion/agent/ai-connection.ts`.

## 2. Offer models live, never from a list in code

Owner's direction (2026-10-18). A hand-kept list went a month without an edit in Potion while three new models came
out, and three products had copied it. Read OpenRouter's model list on the server, cache it about an hour, and filter
it for what the feature needs. `check.sh` warns (`ai-models`) on a source file that names three or more models.

Use the official SDK, [`@openrouter/sdk`](https://www.npmjs.com/package/@openrouter/sdk) (typed, paged, no key needed to
list):

```ts
import { OpenRouter } from '@openrouter/sdk';

const openrouter = new OpenRouter({});

/** Every model OpenRouter lists. Fetch them ALL, then filter here (see the trap below). */
async function listModels() {
  const all = [];
  for await (const page of await openrouter.models.list({})) all.push(...(page.result?.data ?? []));
  return all;
}
```

**Trap:** the list's own filters (`supportedParameters: 'tools'`, …) silently drop every `~maker/family-latest` alias,
even though the aliases take tools (seen 2026-10-18 with `@openrouter/sdk@1.4.25`: 376 models back, no alias among
them). Ask for everything, then filter in code.

There is no shared package for this, on purpose: once the list is live, what is left is a few lines of rules per app,
and they rarely change. The SDK carries the plumbing; this guide carries the rules.

### Filters, by what the feature needs

| The feature needs | Keep a model when |
|---|---|
| an agent with tools (MCP, skills) | `supportedParameters` has `tools` **and** `tool_choice` (the loop uses `tool_choice` to make a turn answer); `contextLength` ≥ 64,000 |
| an answer in text | `architecture.outputModalities` has `text` and no `image` / `audio` |
| a picture attached | `architecture.inputModalities` has `image`: offer the attach button only then, and refuse a picture sent to a model without it |
| a PDF read as it is | `inputModalities` has `file` (otherwise see the PDF trap below) |
| always | the id has no `:` (`:free`, `:batch` answer differently or hours later), does not start with `openrouter/` (its routers pick a model we never see), and has no `expirationDate` (it is retiring) |

A need only one product has stays in that product, written in its own `CLAUDE.md` (Potion's YouTube summaries:
only Gemini, through Google's own providers, takes a YouTube address).

### Defaults and labels

- **The default is a `~maker/family-latest` alias** (`~anthropic/claude-sonnet-latest`): OpenRouter keeps it on the
  newest of the family, so the default never ages and a person who picks one never has to come back.
- **A feature that runs on every keystroke or every dictation picks its default by measuring.** Time and price two or
  three candidates on a real input in dev and keep the fastest that is good enough, even when no alias follows it, with
  the numbers in a comment beside the default. Measured for dictation cleanup (format, 2026-10-18): Gemini 3.1
  Flash-Lite 1.05 s / $0.0003, Claude Haiku Latest 1.9 s / $0.0011, Claude Sonnet Latest 1.2 s / $0.0033. A default
  that is not an alias needs watching: change it when OpenRouter gives it an `expirationDate`.
- Each alias carries **`aliasTarget`** (`{ name: 'Anthropic: Claude Sonnet 5.5', slug: 'anthropic/claude-sonnet-5.5' }`):
  show it, so the person sees what "Latest" is today.
- A picker groups by maker, aliases first in each group, then newest (`created`), and **has a search box**: an agent
  filter leaves a few hundred models.
- A name reads "Maker: Model"; drop the maker when the group already says it.

## 3. Check a choice, and never swap it

- **A write** (the person picks a model) is checked against the live list. When OpenRouter cannot be read, accept any
  well-formed id: the call itself refuses one it does not know.
- **A model the person chose is never swapped for another** (owner's rule, 2026-10-17). It is **gone** when it is missing
  from the whole listing (not only from the filtered offer), or when a call answers that it does not exist. Then:
  - the call refuses: "The model X is no longer available on OpenRouter. Choose another in Settings → AI." (name the
    screen that holds that choice);
  - what the person typed or said is kept;
  - the picker opens, or shows the gone model marked as such;
  - the settings show it too, before anyone sends anything.
- Keep the person's choice stored as it is; only a new choice replaces it.

## 4. Call a model

- Server side only, with the person's key. Send `provider: { require_parameters: true }` with tools, so a provider that
  silently drops them is never picked (the loop would stall), and `usage: { include: true }` to get the cost back.
- **Show the price** of what ran when it finishes: it is their money.
- Map the refusals to words a person can act on:

| OpenRouter answers | Tell the person |
|---|---|
| `402` | Your OpenRouter credits ran out. Add credits on openrouter.ai. |
| `401` / `403` | OpenRouter no longer accepts your key. Reconnect it in Settings → AI. |
| `400` "`<id>` is not a valid model ID" | The model `<id>` is no longer available on OpenRouter. Choose another in … |

- **Attachments** ride on the user message as content parts: a picture as `{ type: 'image_url', image_url: { url: 'data:image/jpeg;base64,…' } }`,
  a PDF as `{ type: 'file', file: { filename, file_data: 'data:application/pdf;base64,…' } }`. Shrink pictures before
  sending (Potion: 1568 px JPEG). A text file is inlined in the message.

## Traps

| You see | Why | Do |
|---|---|---|
| No `~…-latest` alias in the list | The list's server-side filters drop aliases | Fetch all models, filter in code |
| `400 {"error":{"message":"<id> is not a valid model ID"}}` | OpenRouter retired the model since it was chosen | The "choose another" refusal, never a generic "AI call failed" and never a silent switch |
| A PDF costs more than expected | Sent to a model that does not read PDFs, it goes through OpenRouter's default parser, which is paid OCR | Add `plugins: [{ id: 'file-parser', pdf: { engine: 'pdf-text' } }]` (free text parser) |
| `content: null` with a small `max_tokens` | A reasoning model spent the budget thinking | Leave room, or send `reasoning: { effort: 'low' }` |
| `400` on a call that sends `reasoning: { effort: 'none' }` (or `'minimal'`), for Claude Sonnet Latest or Gemini Flash Latest but not for others | The model must think: its listing has `reasoning.mandatory: true` and `supportedEfforts` without `none` | Send the least effort the model lists (`reasoning.supportedEfforts`), or step down on a 400: `none` → `minimal` → `low`. Check first that the 400 is not "is not a valid model ID" (a gone model) |
| A model in the picker that stops answering days later | It had an `expirationDate` | Leave out models with one |
