#!/usr/bin/env python3
"""
Expand pinyintable with common Chinese words and phrases.
"""

import sqlite3
import hashlib

# Database path
DB_PATH = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"

# Common Chinese words and phrases with their pinyin
# Format: (Chinese word, Pinyin)
COMMON_WORDS = [
    # Personal pronouns
    ("我们", "women"),
    ("你们", "nimen"),
    ("他们", "tamen"),
    ("她们", "tamen"),
    ("咱们", "zanmen"),
    ("自己", "ziji"),
    ("大家", "dajia"),

    # Greetings and common phrases
    ("你好", "ni hao"),
    ("您好", "nin hao"),
    ("再见", "zai jian"),
    ("谢谢", "xie xie"),
    ("对不起", "dui bu qi"),
    ("没关系", "mei guan xi"),
    ("不客气", "bu ke qi"),

    # Common verbs
    ("是", "shi"),
    ("有", "you"),
    ("在", "zai"),
    ("去", "qu"),
    ("来", "lai"),
    ("做", "zuo"),
    ("看", "kan"),
    ("说", "shuo"),
    ("想", "xiang"),
    ("要", "yao"),
    ("能", "neng"),
    ("会", "hui"),
    ("可以", "ke yi"),
    ("喜欢", "xi huan"),
    ("爱", "ai"),
    ("知道", "zhi dao"),
    ("认识", "ren shi"),
    ("明白", "ming bai"),
    ("理解", "li jie"),
    ("学习", "xue xi"),
    ("工作", "gong zuo"),
    ("生活", "sheng huo"),
    ("吃饭", "chi fan"),
    ("睡觉", "shui jiao"),
    ("回家", "hui jia"),

    # Time
    ("今天", "jin tian"),
    ("明天", "ming tian"),
    ("昨天", "zuo tian"),
    ("现在", "xian zai"),
    ("以后", "yi hou"),
    ("以前", "yi qian"),
    ("早上", "zao shang"),
    ("晚上", "wan shang"),
    ("中午", "zhong wu"),

    # Places
    ("中国", "zhong guo"),
    ("北京", "bei jing"),
    ("上海", "shang hai"),
    ("家", "jia"),
    ("学校", "xue xiao"),
    ("公司", "gong si"),
    ("医院", "yi yuan"),

    # Common adjectives
    ("好", "hao"),
    ("大", "da"),
    ("小", "xiao"),
    ("多", "duo"),
    ("少", "shao"),
    ("新", "xin"),
    ("老", "lao"),
    ("高", "gao"),
    ("矮", "ai"),
    ("美", "mei"),
    ("漂亮", "piao liang"),
    ("帅", "shuai"),
    ("高兴", "gao xing"),
    ("开心", "kai xin"),
    ("难过", "nan guo"),
    ("重要", "zhong yao"),

    # Numbers and quantities
    ("一点", "yi dian"),
    ("一些", "yi xie"),
    ("什么", "shen me"),
    ("怎么", "zen me"),
    ("为什么", "wei shen me"),
    ("多少", "duo shao"),
    ("几个", "ji ge"),

    # Common conjunctions and particles
    ("和", "he"),
    ("跟", "gen"),
    ("或者", "huo zhe"),
    ("还是", "hai shi"),
    ("但是", "dan shi"),
    ("可是", "ke shi"),
    ("因为", "yin wei"),
    ("所以", "suo yi"),
    ("如果", "ru guo"),
    ("的话", "de hua"),
    ("吗", "ma"),
    ("呢", "ne"),
    ("吧", "ba"),
    ("啊", "a"),

    # Other common words
    ("这个", "zhe ge"),
    ("那个", "na ge"),
    ("这里", "zhe li"),
    ("那里", "na li"),
    ("东西", "dong xi"),
    ("事情", "shi qing"),
    ("问题", "wen ti"),
    ("方法", "fang fa"),
    ("时候", "shi hou"),
    ("地方", "di fang"),
    ("时间", "shi jian"),
    ("钱", "qian"),
    ("名字", "ming zi"),
    ("朋友", "peng you"),
    ("老师", "lao shi"),
    ("学生", "xue sheng"),
    ("父母", "fu mu"),
    ("孩子", "hai zi"),

    # Technology terms
    ("电脑", "dian nao"),
    ("手机", "shou ji"),
    ("网络", "wang luo"),
    ("软件", "ruan jian"),
    ("硬件", "ying jian"),
    ("程序", "cheng xu"),
    ("代码", "dai ma"),
    ("数据", "shu ju"),
    ("文件", "wen jian"),
    ("系统", "xi tong"),
]

def deterministic_hash(s: str) -> int:
    """
    Compute deterministic hash compatible with Swift implementation.
    hash = (hash * 31 + char_code) & 0xFFFFFFFF
    """
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

def main():
    print("Expanding pinyintable with common Chinese words...")

    # Connect to database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check current count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    current_count = cursor.fetchone()[0]
    print(f"Current pinyintable count: {current_count}")

    # Add new words
    added_count = 0
    skipped_count = 0

    for word, pinyin in COMMON_WORDS:
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
        print(f"  Added: {word} ({pinyin})")

    # Commit changes
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

    # Verify some entries
    print("\nVerifying some entries:")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    test_words = [("我们", "women"), ("你好", "ni hao"), ("中国", "zhong guo")]
    for word, pinyin in test_words:
        cursor.execute(
            "SELECT rowid, word, pinyin, shortcut, ping FROM pinyintable WHERE word = ? AND pinyin = ?",
            (word, pinyin)
        )
        result = cursor.fetchone()
        if result:
            print(f"  ✓ {word} ({pinyin}) - rowid:{result[0]}, shortcut:{result[3]}, ping:{result[4]}")
        else:
            print(f"  ✗ {word} ({pinyin}) - NOT FOUND")

    conn.close()

if __name__ == "__main__":
    main()
