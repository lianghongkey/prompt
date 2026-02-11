#!/usr/bin/env python3
"""
Create a Mandarin Pinyin syllable table from existing pinyintable data.
"""

import sqlite3

DB_PATH = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"

def charcode(s: str) -> int:
    """Compute charcode compatible with Swift implementation (a=20, b=21, ..., z=45)."""
    # Each character maps to a code (a=20, b=21, ..., z=45)
    def intercode(c: str) -> int:
        if 'a' <= c <= 'z':
            return ord(c) - ord('a') + 20
        return None

    codes = []
    for char in s.lower():
        code = intercode(char)
        if code is None:
            return None
        codes.append(code)

    # Combine codes: code * 100 + next_code
    result = 0
    for code in codes:
        result = result * 100 + code
    return result

def main():
    print("Extracting pinyin syllables from pinyintable...")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Get all unique pinyin values
    cursor.execute("SELECT DISTINCT pinyin FROM pinyintable")
    pinyins = [row[0] for row in cursor.fetchall()]

    print(f"Found {len(pinyins)} unique pinyin entries")

    # Extract all syllables (split by space)
    syllables = set()
    for pinyin in pinyins:
        # Split pinyin into syllables (space-separated)
        parts = pinyin.split()
        for part in parts:
            if part:
                syllables.add(part)

    print(f"Extracted {len(syllables)} unique syllables")
    print(f"Sample syllables: {sorted(list(syllables))[:20]}")

    # Check if syllabletable exists and what's in it
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='syllabletable'")
    if cursor.fetchone():
        cursor.execute("SELECT COUNT(*) FROM syllabletable")
        old_count = cursor.fetchone()[0]
        print(f"\nExisting syllabletable has {old_count} entries")

        # Check if it has Mandarin pinyin or Cantonese
        cursor.execute("SELECT origin FROM syllabletable LIMIT 10")
        samples = [row[0] for row in cursor.fetchall()]
        print(f"Sample origins: {samples}")

        print("\nClearing old syllabletable...")
        cursor.execute("DELETE FROM syllabletable")
    else:
        print("\nCreating syllabletable...")
        cursor.execute("""
            CREATE TABLE syllabletable (
                code INTEGER PRIMARY KEY,
                tenkey INTEGER,
                token TEXT,
                origin TEXT
            )
        """)

    # Insert syllables
    print(f"\nInserting {len(syllables)} Mandarin pinyin syllables...")

    syllable_list = sorted(syllables)
    insert_count = 0

    for syllable in syllable_list:
        code = charcode(syllable)
        if code is None:
            continue

        # For Mandarin, token and origin are the same (the pinyin syllable)
        # tenkey: T9 keypad mapping
        tenkey_map = {
            'a': 2, 'b': 2, 'c': 2,
            'd': 3, 'e': 3, 'f': 3,
            'g': 4, 'h': 4, 'i': 4,
            'j': 5, 'k': 5, 'l': 5,
            'm': 6, 'n': 6, 'o': 6,
            'p': 7, 'q': 7, 'r': 7, 's': 7,
            't': 8, 'u': 8, 'v': 8,
            'w': 9, 'x': 9, 'y': 9, 'z': 9
        }
        first_char = syllable[0].lower()
        tenkey = tenkey_map.get(first_char, 0)

        try:
            cursor.execute(
                "INSERT INTO syllabletable (code, tenkey, token, origin) VALUES (?, ?, ?, ?)",
                (code, tenkey, syllable, syllable)
            )
            insert_count += 1
        except sqlite3.IntegrityError:
            # Duplicate code, skip
            pass

    conn.commit()

    # Verify
    cursor.execute("SELECT COUNT(*) FROM syllabletable")
    new_count = cursor.fetchone()[0]

    # Check specific syllables
    test_syllables = ["shen", "gan", "me", "zhong", "guo", "ni", "hao"]
    print("\nVerifying test syllables:")
    for syllable in test_syllables:
        code = charcode(syllable)
        cursor.execute("SELECT * FROM syllabletable WHERE code = ?", (code,))
        result = cursor.fetchone()
        if result:
            print(f"  ✓ {syllable}: code={result[0]}, tenkey={result[1]}")
        else:
            print(f"  ✗ {syllable}: NOT FOUND (code={code})")

    conn.close()

    print(f"\nDone!")
    print(f"  Inserted: {insert_count} syllables")
    print(f"  Total in table: {new_count}")

if __name__ == "__main__":
    main()
