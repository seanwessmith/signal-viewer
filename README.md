# signal-viewer

A tool for exporting and viewing Signal chat history with incremental updates.

## Setup

1. Install dependencies:
   - [uv](https://github.com/astral-sh/uv) for Python package management
   - [Bun](https://bun.sh) for running scripts
   - [sigexport](https:/$$/github.com/carderne/sigexport) (installed via uv)

2. Install the project:
   ```bash
   bun install
   ```

## Export Commands

### Full Export (Replace Everything)
```bash
bun run chat:get:full
```
Exports your complete Signal history to `./signal-chats`. This will overwrite any existing data.

### Incremental Export (Standard)
```bash
bun run chat:get
```
Exports all messages from Signal and merges only new messages with existing data. Preserves your chat history while adding new messages.

### Fast Incremental Export
```bash
bun run chat:fast
```
Optimized version that:
- Skips chats with no new messages (compares file sizes and last messages)
- Processes chats in parallel batches for speed
- Uses MD5 hashing for efficient deduplication
- Typically 3-5x faster than standard export

### Export Specific Chats
```bash
./export-new-chats-fast.sh --chats "Fam,Mom,Friends"
```
Only exports and merges specific chats (comma-separated list).

## How It Works

1. Exports Signal data to a temporary directory
2. Compares new messages with existing ones
3. Merges only new messages (no duplicates)
4. Copies new media files
5. Cleans up temporary files

## Directory Structure

```
signal-chats/
├── ChatName1/
│   ├── data.json       # Message data (JSONL format)
│   ├── media/          # Attachments and media files
│   ├── chat.md         # Markdown format (if generated)
│   └── index.html      # HTML viewer (if generated)
└── .last-export-metadata  # Export statistics
```

## Notes

- Messages are deduplicated based on date + sender + body
- No backups are created (you can always re-export from Signal)
- "No file to copy" warnings are suppressed (these are missing attachments)
