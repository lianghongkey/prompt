#!/usr/bin/env python3
"""
Safe database updater - creates a writable copy and updates it.
"""

import os
import shutil
import sqlite3

# Paths
BUNDLE_DB_PATH = "/Users/colin/develop/TypeDuck-Mac/.build/Build/Products/Debug/TypeDuck.app/Contents/Resources/CoreIME_CoreIME.bundle/Contents/Resources/imedb.sqlite3"
DB_DIR = os.path.expanduser("~/Library/Application Support/TypeDuck")
UPDATED_DB_PATH = os.path.join(DB_DIR, "imedb.sqlite3")

def create_writable_copy():
    """Create a writable copy of the database in user Library."""
    print(f"Original DB: {BUNDLE_DB_PATH}")
    print(f"Creating writable copy at: {UPDATED_DB_PATH}")

    # Ensure target directory exists
    os.makedirs(DB_DIR, exist_ok=True)

    # Copy database to user Library
    try:
        shutil.copy2(BUNDLE_DB_PATH, UPDATED_DB_PATH)
        print("✓ Database copied successfully")

        # Verify the copy
        conn = sqlite3.connect(UPDATED_DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM pinyintable")
        count = cursor.fetchone()[0]
        conn.close()
        print(f"Verified: {count} entries in copy")

    except Exception as e:
        print(f"✗ Copy failed: {e}")
        return False

    return True

def add_common_words():
    """Add common Chinese words to database."""

    # Common words to add (same as before)
    common_words = [
        ("我们", "wo men"), ("你们", "ni men"), ("他们", "ta men"),
        ("你好", "ni hao"), ("您好", "nin hao"), ("谢谢", "xie xie"),
        ("早上好", "zao shang hao"), ("再见", "zai jian"), ("对不起", "dui bu qi"),
        ("没关系", "mei guan xi"), ("不客气", "bu ke qi"),
        ("喜欢", "xi huan"), ("知道", "zhi dao"), ("认识", "ren shi"),
        ("明白", "ming bai"), ("理解", "li jie"), ("学习", "xue xi"),
        ("工作", "gong zuo"), ("吃饭", "chi fan"), ("睡觉", "shui jiao"),
        ("回家", "hui jia"), ("今天", "jin tian"), ("明天", "ming tian"),
        ("现在", "xian zai"), ("时间", "shi jian"),
        ("电脑", "dian nao"), ("手机", "shou ji"),
        ("网络", "wang luo"), ("软件", "ruan jian"),
        ("程序", "cheng xu"), ("代码", "dai ma"), ("数据", "shu ju"),
        ("文件", "wen jian"), ("系统", "xi tong"), ("高兴", "gao xing"),
        ("快乐", "kai xin"), ("难过", "nan guo"), ("重要", "zhong yao"),
        ("中国", "zhong guo"), ("北京", "bei jing"), ("学校", "xue xiao"),
        ("医院", "yi yuan"), ("公司", "gong si"), ("银行", "yin hang"),
        ("商店", "shang dian"), ("老师", "lao shi"), ("学生", "xue sheng"),
        ("朋友", "peng you"), ("父母", "fu mu"), ("孩子", "hai zi"),
        ("医生", "yi sheng"), ("护士", "hu shi"), ("警察", "jing cha"),
        ("司机", "si ji"), ("服务员", "fu wu"), ("飞机", "fei ji"),
        ("自行车", "zi xing che"), ("地铁", "di tie"),
    ]

    # Try to use writable copy
    db_path = UPDATED_DB_PATH

    # First try creating writable copy
    if not create_writable_copy():
        print("\n❌ Failed to create writable copy")
        print("Falling back to script method...")
        return

    print("\nAdding words to database...")

    # Connect to writable copy
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        added_count = 0
        skipped_count = 0

        for word, pinyin in common_words:
            # Check if already exists
            cursor.execute(
                "SELECT rowid FROM pinyintable WHERE word = ? AND pinyin = ?",
                (word, pinyin)
            )
            if cursor.fetchone():
                skipped_count += 1
                continue

            # Calculate ping and shortcut
            ping = deterministic_hash(pinyin)
            shortcut = get_shortcut(pinyin)

            # Insert into database
            cursor.execute(
                "INSERT OR IGNORE INTO pinyintable (word, pinyin, shortcut, ping) VALUES (?, ?, ?, ?)",
                (word, pinyin, shortcut, ping)
            )
            added_count += 1

            if added_count % 100 == 0:
                print(f"  Added: {word} ({pinyin})")

        conn.commit()

        # Verify
        cursor.execute("SELECT COUNT(*) FROM pinyintable")
        new_count = cursor.fetchone()[0]

        conn.close()

        print(f"\nDone!")
        print(f"  Added: {added_count} words")
        print(f"  Skipped: {skipped_count} words")
        print(f"  Total: {new_count}")

        return True

    except Exception as e:
        print(f"\n❌ Error updating database: {e}")
        return False

def get_shortcut(pinyin: str) -> int:
    """Get shortcut code from first character of pinyin."""
    if not pinyin:
        return None
    first_char = pinyin[0].lower()
    if 'a' <= first_char <= 'z':
        return ord(first_char) - ord('a') + 20
    return None

def deterministic_hash(s: str) -> int:
    """Compute deterministic hash compatible with Swift implementation."""
    hash_value = 0
    for char in s.encode('utf-8'):
        hash_value = (hash_value * 31 + char) & 0xFFFFFFFF
    return hash_value

def get_intercode(char: str) -> int:
    """Get intercode for a character (a=20, b=21, ..., z=45)."""
    if 'a' <= char <= 'z':
        return ord(char) - ord('a') + 20
    return None

def main():
    """Main entry point."""
    add_common_words()

if __name__ == "__main__":
    main()
