#!/bin/bash

# Fast incremental Signal export - only processes chats with new messages
# Usage: ./export-new-chats-fast.sh [--chats "chat1,chat2"]

MAIN_DIR="./signal-chats"
METADATA_FILE="./signal-chats/.last-export-metadata"

# Parse command line arguments
SPECIFIC_CHATS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --chats)
            SPECIFIC_CHATS="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Get current date for archiving
DATE=$(date +"%Y%m%d_%H%M%S")
TEMP_EXPORT_DIR="./signal-export-temp-${DATE}"

# Clean up any old temp directories
rm -rf ./signal-export-temp-* 2>/dev/null || true

# Build sigexport command
EXPORT_CMD="uv run sigexport"

# Add specific chats filter if specified
if [ -n "$SPECIFIC_CHATS" ]; then
    EXPORT_CMD="$EXPORT_CMD --chats \"$SPECIFIC_CHATS\""
fi

EXPORT_CMD="$EXPORT_CMD \"$TEMP_EXPORT_DIR\""

# Export messages
echo "Exporting Signal messages to $TEMP_EXPORT_DIR..."
if [ -n "$SPECIFIC_CHATS" ]; then
    echo "  Filtering to chats: $SPECIFIC_CHATS"
fi

eval $EXPORT_CMD 2>&1 | grep -v "No file to copy" || true

# Check if export was successful
if [ ! -d "$TEMP_EXPORT_DIR" ] || [ -z "$(ls -A $TEMP_EXPORT_DIR 2>/dev/null)" ]; then
    echo "Error: Export failed or no data exported"
    exit 1
fi

# Create a Bun script for fast parallel processing
cat > /tmp/merge-signal-chats.js << 'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const tempExportDir = process.argv[2];
const mainDir = process.argv[3];
const date = process.argv[4];

// Get list of exported chats
const exportedChats = fs.readdirSync(tempExportDir)
    .filter(f => fs.statSync(path.join(tempExportDir, f)).isDirectory());

console.log(`Found ${exportedChats.length} chats to process`);

// Process chats in parallel batches
const BATCH_SIZE = 10;
let totalNewMessages = 0;
let processedChats = 0;

async function processChat(chatName) {
    const exportPath = path.join(tempExportDir, chatName);
    const mainPath = path.join(mainDir, chatName);
    const exportDataFile = path.join(exportPath, 'data.json');
    const mainDataFile = path.join(mainPath, 'data.json');
    
    if (!fs.existsSync(exportDataFile)) {
        return { chat: chatName, newMessages: 0, skipped: true };
    }
    
    // Quick check: if chat doesn't exist in main, it's all new
    if (!fs.existsSync(mainPath)) {
        console.log(`Adding new chat: ${chatName}`);
        fs.cpSync(exportPath, mainPath, { recursive: true });
        const newMessages = fs.readFileSync(exportDataFile, 'utf8').trim().split('\n').length;
        return { chat: chatName, newMessages, isNew: true };
    }
    
    // Quick size check - if export is smaller, likely no new messages
    const exportSize = fs.statSync(exportDataFile).size;
    const mainSize = fs.existsSync(mainDataFile) ? fs.statSync(mainDataFile).size : 0;
    
    if (exportSize <= mainSize) {
        // Double check by comparing last messages
        const exportLines = fs.readFileSync(exportDataFile, 'utf8').trim().split('\n');
        const mainLines = fs.readFileSync(mainDataFile, 'utf8').trim().split('\n');
        
        if (exportLines.length <= mainLines.length) {
            const lastExport = exportLines[exportLines.length - 1];
            const lastMain = mainLines[mainLines.length - 1];
            
            if (lastExport === lastMain) {
                return { chat: chatName, newMessages: 0, skipped: true };
            }
        }
    }
    
    // Skip archiving - not needed since we can re-export from Signal
    
    // Merge messages
    const existingData = fs.existsSync(mainDataFile) 
        ? fs.readFileSync(mainDataFile, 'utf8').trim().split('\n')
        : [];
    
    const newData = fs.readFileSync(exportDataFile, 'utf8').trim().split('\n');
    
    // Create a Set of existing message hashes for fast lookup
    const existingHashes = new Set();
    existingData.forEach(line => {
        if (line) {
            try {
                const msg = JSON.parse(line);
                const hash = crypto.createHash('md5')
                    .update(msg.date + msg.sender + msg.body)
                    .digest('hex');
                existingHashes.add(hash);
            } catch {}
        }
    });
    
    // Add only new messages
    const mergedData = [...existingData];
    let addedCount = 0;
    
    newData.forEach(line => {
        if (line) {
            try {
                const msg = JSON.parse(line);
                const hash = crypto.createHash('md5')
                    .update(msg.date + msg.sender + msg.body)
                    .digest('hex');
                if (!existingHashes.has(hash)) {
                    mergedData.push(line);
                    addedCount++;
                }
            } catch {}
        }
    });
    
    if (addedCount > 0) {
        // Ensure directory exists
        fs.mkdirSync(mainPath, { recursive: true });
        
        // Write merged data
        fs.writeFileSync(mainDataFile, mergedData.join('\n') + '\n');
        
        // Copy new media files if they exist
        const exportMediaDir = path.join(exportPath, 'media');
        const mainMediaDir = path.join(mainPath, 'media');
        
        if (fs.existsSync(exportMediaDir)) {
            fs.mkdirSync(mainMediaDir, { recursive: true });
            const mediaFiles = fs.readdirSync(exportMediaDir);
            
            mediaFiles.forEach(file => {
                const srcFile = path.join(exportMediaDir, file);
                const destFile = path.join(mainMediaDir, file);
                if (!fs.existsSync(destFile)) {
                    fs.copyFileSync(srcFile, destFile);
                }
            });
        }
    }
    
    return { chat: chatName, newMessages: addedCount };
}

async function processBatch(batch) {
    const results = await Promise.all(batch.map(chat => processChat(chat)));
    return results;
}

async function main() {
    const startTime = Date.now();
    
    // Process in batches
    for (let i = 0; i < exportedChats.length; i += BATCH_SIZE) {
        const batch = exportedChats.slice(i, i + BATCH_SIZE);
        const results = await processBatch(batch);
        
        results.forEach(result => {
            processedChats++;
            if (!result.skipped && result.newMessages > 0) {
                console.log(`${result.isNew ? 'Added new chat' : 'Merged'} ${result.chat}: ${result.newMessages} new messages`);
                totalNewMessages += result.newMessages;
            }
        });
    }
    
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`\nProcessed ${processedChats} chats in ${elapsed}s`);
    console.log(`Total new messages: ${totalNewMessages}`);
    
    // Save metadata
    const metadata = {
        lastExport: new Date().toISOString(),
        chatsProcessed: processedChats,
        newMessages: totalNewMessages,
        elapsed: elapsed
    };
    fs.writeFileSync(path.join(mainDir, '.last-export-metadata'), JSON.stringify(metadata, null, 2));
}

main().catch(console.error);
EOF

# Run the merge script with Bun
echo "Merging chats..."
bun /tmp/merge-signal-chats.js "$TEMP_EXPORT_DIR" "$MAIN_DIR" "$DATE"

# Clean up
echo "Cleaning up..."
rm -rf "$TEMP_EXPORT_DIR"
rm -f /tmp/merge-signal-chats.js

echo "Export complete!"
if [ -f "$METADATA_FILE" ]; then
    echo "Last export details:"
    cat "$METADATA_FILE"
fi