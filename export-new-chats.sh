#!/bin/bash

# Script to export only new Signal messages since last export
# Usage: ./export-new-chats.sh

EXPORT_DIR="./signal-chats-new"
MAIN_DIR="./signal-chats"

# Get current date for archiving
DATE=$(date +"%Y%m%d_%H%M%S")

# Use a unique temporary directory with timestamp
TEMP_EXPORT_DIR="./signal-export-temp-${DATE}"

# Clean up any old temp directories
rm -rf ./signal-export-temp-* 2>/dev/null || true

# Export new messages to temporary directory
echo "Exporting Signal messages to $TEMP_EXPORT_DIR..."
uv run sigexport "$TEMP_EXPORT_DIR" 2>&1 | grep -v "No file to copy" || true

# Check if export was successful
if [ ! -d "$TEMP_EXPORT_DIR" ] || [ -z "$(ls -A $TEMP_EXPORT_DIR 2>/dev/null)" ]; then
    echo "Error: Export failed or no data exported"
    exit 1
fi

# For each chat directory in the new export
for chat_dir in "$TEMP_EXPORT_DIR"/*; do
    if [ -d "$chat_dir" ]; then
        chat_name=$(basename "$chat_dir")
        
        # If this chat exists in main directory
        if [ -d "$MAIN_DIR/$chat_name" ]; then
            echo "Merging $chat_name..."
            
            # Skip archiving - not needed since we can re-export from Signal
            
            # Merge JSON files (append new messages to existing)
            if [ -f "$TEMP_EXPORT_DIR/$chat_name/data.json" ]; then
                # Use bun to merge the JSONL files
                bun -e "
                    const fs = require('fs');
                    const path = require('path');
                    
                    const mainFile = '$MAIN_DIR/$chat_name/data.json';
                    const newFile = '$TEMP_EXPORT_DIR/$chat_name/data.json';
                    
                    // Read existing messages
                    const existingData = fs.existsSync(mainFile) 
                        ? fs.readFileSync(mainFile, 'utf8').trim().split('\\n')
                        : [];
                    
                    // Read new messages
                    const newData = fs.readFileSync(newFile, 'utf8').trim().split('\\n');
                    
                    // Parse to get timestamps for deduplication
                    const existingMessages = new Set();
                    existingData.forEach(line => {
                        try {
                            const msg = JSON.parse(line);
                            existingMessages.add(msg.date + msg.sender + msg.body);
                        } catch {}
                    });
                    
                    // Add only new messages
                    const mergedData = [...existingData];
                    let addedCount = 0;
                    newData.forEach(line => {
                        try {
                            const msg = JSON.parse(line);
                            const key = msg.date + msg.sender + msg.body;
                            if (!existingMessages.has(key)) {
                                mergedData.push(line);
                                addedCount++;
                            }
                        } catch {}
                    });
                    
                    // Write merged data
                    fs.writeFileSync(mainFile, mergedData.join('\\n') + '\\n');
                    console.log('Added', addedCount, 'new messages to', '$chat_name');
                "
            fi
            
            # Copy new media files
            if [ -d "$TEMP_EXPORT_DIR/$chat_name/media" ]; then
                cp -n "$TEMP_EXPORT_DIR/$chat_name/media/"* "$MAIN_DIR/$chat_name/media/" 2>/dev/null || true
            fi
            
        else
            # New chat, copy entire directory
            echo "Adding new chat: $chat_name"
            cp -r "$chat_dir" "$MAIN_DIR/"
        fi
    fi
done

# Clean up temporary directory
echo "Cleaning up temporary export directory..."
rm -rf "$TEMP_EXPORT_DIR"

echo "Export complete! New messages have been merged."