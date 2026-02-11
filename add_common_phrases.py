#!/usr/bin/env python3
"""
Clean, comprehensive Chinese pinyin dictionary.
Removes all duplicates and ensures quality entries.
"""

import sqlite3

# Database path
DB_PATH = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"

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

def get_shortcut(pinyin: str) -> int:
    """Get shortcut code from first character of pinyin."""
    if not pinyin:
        return None
    first_char = pinyin[0].lower()
    return get_intercode(first_char)

# Comprehensive word list - no duplicates
REAL_WORDS = [
    # ===== Personal pronouns and people =====
    ("我们", "wo men"), ("你们", "ni men"), ("他们", "ta men"), ("自己", "zi ji"),
    ("大家", "da jia"), ("我", "wo"), ("你", "ni"), ("他", "ta"),
    ("她", "ta"), ("它", "ta"), ("谁", "shei"), ("什么人", "shen me ren"),

    # ===== Greetings =====
    ("你好", "ni hao"), ("您好", "nin hao"), ("大家好", "da jia hao"),
    ("再见", "zai jian"), ("谢谢", "xie xie"), ("不客气", "bu ke qi"),

    # ===== Politeness =====
    ("对不起", "dui bu qi"), ("抱歉", "bao qian"), ("不好意思", "bu hao yi si"),

    # ===== Common verbs =====
    ("去", "qu"), ("来", "lai"), ("回", "hui"), ("到", "dao"),
    ("做", "zuo"), ("看", "kan"), ("说", "shuo"), ("听", "ting"),
    ("想", "xiang"), ("要", "yao"), ("能", "neng"), ("会", "hui"),
    ("可以", "ke yi"), ("喜欢", "xi huan"), ("爱", "ai"), ("知道", "zhi dao"),
    ("认识", "ren shi"), ("明白", "ming bai"), ("理解", "li jie"),
    ("学习", "xue xi"), ("工作", "gong zuo"), ("吃饭", "chi fan"),
    ("睡觉", "shui jiao"), ("休息", "xiu xi"),

    # ===== Time =====
    ("今天", "jin tian"), ("明天", "ming tian"), ("昨天", "zuo tian"),
    ("现在", "xian zai"), ("以后", "yi hou"), ("以前", "yi qian"),

    # ===== Places =====
    ("中国", "zhong guo"), ("北京", "bei jing"), ("上海", "shang hai"),
    ("家", "jia"), ("这里", "zhe li"), ("那里", "na li"),

    # ===== People =====
    ("人", "ren"), ("朋友", "peng you"), ("老师", "lao shi"), ("学生", "xue sheng"),
    ("父母", "fu mu"), ("孩子", "hai zi"),

    # ===== Common objects =====
    ("东西", "dong xi"), ("事情", "shi qing"), ("问题", "wen ti"),
    ("手机", "shou ji"), ("电脑", "dian nao"), ("电话", "dian hua"),

    # ===== Descriptive =====
    ("好", "hao"), ("大", "da"), ("小", "xiao"), ("多", "duo"),
    ("漂亮", "piao liang"), ("帅", "shuai"), ("美", "mei"),
    ("高兴", "gao xing"), ("开心", "kai xin"), ("难过", "nan guo"),

    # ===== Question words =====
    ("什么", "shen me"), ("怎么", "zen me"), ("为什么", "wei shen me"),

    # ===== Connectors =====
    ("和", "he"), ("还是", "hai shi"),

    # ===== Technology =====
    ("网络", "wang luo"), ("软件", "ruan jian"), ("系统", "xi tong"),
    ("文件", "wen jian"), ("程序", "cheng xu"), ("代码", "dai ma"),
]

def main():
    print("Adding comprehensive Chinese words to pinyintable...")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check current count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    current_count = cursor.fetchone()[0]
    print(f"Current pinyintable count: {current_count}")

    # Add words
    added_count = 0
    skipped_count = 0

    for word, pinyin in REAL_WORDS:
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
            "INSERT INTO pinyintable (word, pinyin, shortcut, ping) VALUES (?, ?, ?, ?)",
            (word, pinyin, shortcut, ping)
        )
        added_count += 1

    # Commit every 1000 words to avoid issues
        if added_count % 1000 == 0:
            conn.commit()

    # Verify new count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    new_count = cursor.fetchone()[0]

    conn.close()

    print(f"\nSummary:")
    print(f"  Added: {added_count} words")
    print(f"  Skipped (already exists): {skipped_count} words")
    print(f"  Previous total: {current_count}")
    print(f"  New total: {new_count}")

    # Show some examples
    print("\nSample words added:")
    samples = [("我们", "wo men"), ("你好", "ni hao"), ("谢谢", "xie xie"),
               ("吃饭", "chi fan"), ("睡觉", "shui jiao"), ("工作", "gong zuo")]
    for word, expected_pinyin in samples:
        cursor.execute(
            "SELECT pinyin FROM pinyintable WHERE word = ? LIMIT 3",
            (word,)
        )
        results = cursor.fetchall()
        if results:
            pinyins = [r[0] for r in results]
            print(f"  ✓ {word}: {', '.join(pinyins)}")
        else:
            print(f"  ✗ {word}: NOT FOUND")

if __name__ == "__main__":
    main()
