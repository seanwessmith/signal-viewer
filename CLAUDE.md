---
description: Use Bun instead of Node.js, npm, pnpm, or vite.
globs: "*.ts, *.tsx, *.html, *.css, *.js, *.jsx, package.json"
alwaysApply: false
---

# signal-viewer

A personal data analytics tool for exporting, archiving, and analyzing Signal chat history. Provides incremental syncing with deduplication, semantic tagging, link extraction, and daily digest generation.

## Project Structure

```
├── export-new-chats.sh       # Basic incremental export with deduplication
├── export-new-chats-fast.sh  # Optimized parallel batch processor (~3-5x faster)
├── main.py                   # Python message parser, DuckDB loader, link extractor
├── digest.ts                 # TypeScript daily digest generator with semantic tagging
├── index.ts                  # Simple JSONL parser for testing
├── signal-chats/             # Archived messages (per-chat directories)
├── digests/                  # Generated markdown digests
└── messages.duckdb           # DuckDB database with parsed messages
```

## Data Flow

1. `sigexport` extracts Signal data → temporary directory
2. `export-new-chats*.sh` merges & deduplicates → `signal-chats/`
3. `main.py` parses JSONL, extracts links, applies tags → `messages.duckdb`
4. `digest.ts` queries DuckDB → generates markdown digests

## Key Technologies

- **Bun** - Primary TypeScript runtime
- **DuckDB** - Embedded SQL database for message storage/querying
- **Python/uv** - Data parsing and optional LLM integration
- **sigexport** - Upstream Signal data extractor

## Message Format

Messages are JSONL with fields: `date`, `sender`, `body`, `quote`, `sticker`, `reactions`, `attachments`. Deduplication key: `date + sender + body` (MD5 hashed).

## Semantic Tagging

Pattern-based detection for: `[EVENT]`, `[ASK]`, `[OFFER]`, `[BUILD]`, `[LINK]`, `[RESEARCH]`

## Environment Variables

- `GROK_API_KEY` / `GROK_BASE_URL` - Optional LLM for TL;DR summaries in main.py

---

## Bun Preferences

Default to using Bun instead of Node.js.

- Use `bun <file>` instead of `node <file>` or `ts-node <file>`
- Use `bun test` instead of `jest` or `vitest`
- Use `bun build <file.html|file.ts|file.css>` instead of `webpack` or `esbuild`
- Use `bun install` instead of `npm install` or `yarn install` or `pnpm install`
- Use `bun run <script>` instead of `npm run <script>` or `yarn run <script>` or `pnpm run <script>`
- Bun automatically loads .env, so don't use dotenv.

## APIs

- `Bun.serve()` supports WebSockets, HTTPS, and routes. Don't use `express`.
- `bun:sqlite` for SQLite. Don't use `better-sqlite3`.
- `Bun.redis` for Redis. Don't use `ioredis`.
- `Bun.sql` for Postgres. Don't use `pg` or `postgres.js`.
- `WebSocket` is built-in. Don't use `ws`.
- Prefer `Bun.file` over `node:fs`'s readFile/writeFile
- Bun.$`ls` instead of execa.

## Testing

Use `bun test` to run tests.

```ts#index.test.ts
import { test, expect } from "bun:test";

test("hello world", () => {
  expect(1).toBe(1);
});
```

## Frontend

Use HTML imports with `Bun.serve()`. Don't use `vite`. HTML imports fully support React, CSS, Tailwind.

Server:

```ts#index.ts
import index from "./index.html"

Bun.serve({
  routes: {
    "/": index,
    "/api/users/:id": {
      GET: (req) => {
        return new Response(JSON.stringify({ id: req.params.id }));
      },
    },
  },
  // optional websocket support
  websocket: {
    open: (ws) => {
      ws.send("Hello, world!");
    },
    message: (ws, message) => {
      ws.send(message);
    },
    close: (ws) => {
      // handle close
    }
  },
  development: {
    hmr: true,
    console: true,
  }
})
```

HTML files can import .tsx, .jsx or .js files directly and Bun's bundler will transpile & bundle automatically. `<link>` tags can point to stylesheets and Bun's CSS bundler will bundle.

```html#index.html
<html>
  <body>
    <h1>Hello, world!</h1>
    <script type="module" src="./frontend.tsx"></script>
  </body>
</html>
```

With the following `frontend.tsx`:

```tsx#frontend.tsx
import React from "react";

// import .css files directly and it works
import './index.css';

import { createRoot } from "react-dom/client";

const root = createRoot(document.body);

export default function Frontend() {
  return <h1>Hello, world!</h1>;
}

root.render(<Frontend />);
```

Then, run index.ts

```sh
bun --hot ./index.ts
```

For more information, read the Bun API docs in `node_modules/bun-types/docs/**.md`.
