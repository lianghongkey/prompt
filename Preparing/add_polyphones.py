#!/usr/bin/env python3
"""
Add polyphone (多音字) entries to pinyin.txt
"""

def deterministic_hash(text):
    """Deterministic hash compatible with Swift implementation"""
    hash_value = 0
    for char in text.encode('utf-8'):
        hash_value = ((hash_value * 31) + char) & 0xFFFFFFFF
    return hash_value if hash_value > 0 else 1

def get_intercode(char):
    """Get intercode for a character (a=20, b=21, ..., z=45)"""
    if 'a' <= char <= 'z':
        return ord(char) - ord('a') + 20
    return None

# Define polyphones to add: (character, new_pinyin)
# Only add if the pinyin doesn't already exist in the file
polyphones_to_add = [
    ("了", "le"),       # 了解 (liao3jie3), 完了 (wan2le5)
    ("还", "huan"),     # 还书 (huan2shu1), 还是 (hai2shi4)
    ("得", "dei"),      # 得亏 (dei3kui1), 得到 (de2dao4)
    ("传", "zhuan"),    # 传记 (zhuan4ji4), 传说 (chuan2shuo1)
    ("给", "ji"),       # 给��� (ji3yu3), 给你 (gei3ni3)
    ("觉", "jiao"),     # 睡觉 (shui4jiao4), 感觉 (gan3jue2)
    ("乐", "yue"),      # 音乐 (yin1yue4), 快乐 (kuai4le4)
    ("没", "mo"),       # 没收 (mo4shou1), 没有 (mei2you3)
    ("省", "xing"),     # 反省 (fan3xing3), 省份 (sheng3fen4)
    ("似", "shi"),      # 似的 (shi4de5), 似乎 (si4hu1)
    ("说", "shui"),     # 说服 (shui4fu2), 说话 (shuo1hua4)
    ("着", "zhao"),     # 着急 (zhao2ji2), 着手 (zhuo2shou3)
    ("着", "zhuo"),     # 着陆 (zhuo2lu4), 着想 (zhuo2xiang3)
]

def main():
    pinyin_file = "Sources/Preparing/Resources/pinyin.txt"

    # Read existing file
    with open(pinyin_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Parse existing entries to check what already exists
    existing_entries = set()
    for line in lines:
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            char, pinyin = parts[0], parts[1]
            existing_entries.add((char, pinyin))

    # Find entries to add
    entries_to_add = []
    for char, pinyin in polyphones_to_add:
        if (char, pinyin) not in existing_entries:
            shortcut = get_intercode(pinyin[0])
            ping = deterministic_hash(pinyin)
            entry = f"{char}\t{pinyin}\t{shortcut}\t{ping}\n"
            entries_to_add.append((char, entry))
            print(f"Will add: {char} {pinyin}")
        else:
            print(f"Already exists: {char} {pinyin}")

    if not entries_to_add:
        print("\nNo new entries to add!")
        return

    # Insert new entries right after the first occurrence of each character
    new_lines = []
    added_chars = set()

    for line in lines:
        new_lines.append(line)
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            char = parts[0]
            # Check if we have entries to add for this character
            if char not in added_chars:
                for add_char, add_entry in entries_to_add:
                    if add_char == char:
                        new_lines.append(add_entry)
                        added_chars.add(char)

    # Write back to file
    with open(pinyin_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

    print(f"\nAdded {len(added_chars)} polyphone entries successfully!")
    print("Please rebuild the database with: cd Preparing && swift run -c release")

if __name__ == "__main__":
    main()
