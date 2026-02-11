#!/usr/bin/env python3
"""
Convert Cantonese lexicontable to Mandarin pinyin table.
Extracts multi-character words from lexicontable and converts to pinyin.
"""

import sqlite3
import subprocess
import sys

# Try to install xpinyin if not available
try:
    from xpinyin import Pinyin
except ImportError:
    print("Installing xpinyin...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "xpinyin"])
    from xpinyin import Pinyin

def extract_and_convert():
    """Extract multi-character words and convert to pinyin."""
    db_path = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Extract words with 2-4 characters
    cursor.execute("""
        SELECT word, romanization
        FROM lexicontable
        WHERE length(word) >= 2 AND length(word) <= 4
        ORDER BY frequency DESC
        LIMIT 10000
    """)

    # Read existing pinyin.txt to avoid duplicates
    existing_pinyin = set()
    pinyin_txt_path = "/Users/colin/develop/TypeDuck-Mac/Preparing/Sources/Preparing/Resources/pinyin.txt"
    try:
        with open(pinyin_txt_path, 'r', encoding='utf-8') as f:
            for line in f:
                if '\t' in line:
                    word = line.split('\t')[0]
                    existing_pinyin.add(word)
    except FileNotFoundError:
        pass

    pinyin_converter = Pinyin()

    # Convert and append new entries (2-column format for Pinyin.swift)
    new_entries = []
    for row in cursor.fetchall():
        word, jyutping = row
        if word not in existing_pinyin:
            # Use xpinyin to convert Chinese characters to pinyin
            # get_pinyin(word, splitter=' ') returns space-separated pinyin: "zhong guo"
            pinyin_str = pinyin_converter.get_pinyin(word, splitter=' ')
            new_entries.append(f"{word}\t{pinyin_str}")

    conn.close()

    # Append to pinyin.txt
    with open(pinyin_txt_path, 'a', encoding='utf-8') as f:
        for entry in new_entries:
            f.write(entry + '\n')

    print(f"Added {len(new_entries)} multi-character words to pinyin.txt")
    print("\nExample entries:")
    for entry in new_entries[:20]:
        print(f"  {entry}")

if __name__ == "__main__":
    extract_and_convert()
