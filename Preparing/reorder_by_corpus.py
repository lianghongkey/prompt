#!/usr/bin/env python3
"""
基于现代汉语语料库词频表重新排序 pinyin.txt
使用真实的语料库统计数据
"""

import sys
import csv

def load_frequency_data(csv_file):
    """从CSV文件加载词频数据"""
    print(f"正在加载词频数据: {csv_file}")

    char_freq = {}
    word_freq = {}

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 3:
                rank_str, word, freq_str = row[0], row[1], row[2]
                try:
                    rank = int(rank_str)
                    freq = int(freq_str)

                    # 单字
                    if len(word) == 1:
                        if word not in char_freq:
                            char_freq[word] = rank
                    # 词组
                    else:
                        if word not in word_freq:
                            word_freq[word] = rank

                except ValueError:
                    continue

    print(f"  加载了 {len(char_freq)} 个单字")
    print(f"  加载了 {len(word_freq)} 个词组")

    return char_freq, word_freq

def get_char_frequency_score(char, char_freq):
    """获取单字的频率分数"""
    if char in char_freq:
        return char_freq[char]
    else:
        # 未知字符，给予很低的优先级
        return 100000 + (hash(char) % 900000)

def get_word_frequency_score(word, char_freq, word_freq):
    """获取词组的频率分数"""
    word_len = len(word)

    # 单字
    if word_len == 1:
        return get_char_frequency_score(word, char_freq)

    # 词组在词频表中
    if word in word_freq:
        # 词组的排名，但要确保在单字之后
        # 最高频的单字大约在前5000，所以词组从10000开始
        return 10000 + word_freq[word]

    # 未知词组，根据首字频率和长度估算
    first_char_score = get_char_frequency_score(word[0], char_freq)

    # 基础分数
    if first_char_score < 5000:
        base_score = 50000 + first_char_score * 10
    else:
        base_score = first_char_score * 10

    # 长度惩罚
    length_penalty = (word_len - 2) * 50000

    # 如果所有字都是常用字（前10000），降低惩罚
    all_common = all(
        char in char_freq and char_freq[char] < 10000
        for char in word
    )
    if all_common:
        length_penalty = length_penalty // 3

    # 添加哈希值避免相同分数
    hash_offset = hash(word) % 100

    return base_score + length_penalty + hash_offset

def load_pinyin_data(pinyin_file):
    """加载拼音数据"""
    print(f"\n正在加载拼音数据: {pinyin_file}")

    try:
        from xpinyin import Pinyin
        pinyin_converter = Pinyin()
        has_xpinyin = True
    except ImportError:
        print("  警告: xpinyin 未安装，无法为新词条生成拼音")
        has_xpinyin = False
        pinyin_converter = None

    entries = []
    existing_words = set()

    with open(pinyin_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) != 4:
                print(f"  警告: 第 {line_num} 行格式不正确，跳过")
                continue

            word, pinyin, shortcut, hash_val = parts
            existing_words.add(word)

            entries.append({
                'word': word,
                'pinyin': pinyin,
                'shortcut': shortcut,
                'hash': hash_val,
                'original_line': line_num
            })

            if line_num % 100000 == 0:
                print(f"  已处理 {line_num} 行...")

    print(f"  共加载 {len(entries)} 条词条")

    return entries, existing_words, pinyin_converter if has_xpinyin else None

def calculate_shortcut(text):
    """计算快捷码"""
    LETTER_TO_CODE = {
        'a': 20, 'b': 21, 'c': 22, 'd': 23, 'e': 24, 'f': 25, 'g': 26, 'h': 27, 'i': 28,
        'j': 29, 'k': 30, 'l': 31, 'm': 32, 'n': 33, 'o': 34, 'p': 35, 'q': 36, 'r': 37,
        's': 38, 't': 39, 'u': 40, 'v': 41, 'w': 42, 'x': 43, 'y': 44, 'z': 45
    }

    codes = []
    for char in text:
        if char in LETTER_TO_CODE:
            codes.append(str(LETTER_TO_CODE[char]))

    return ''.join(codes) if codes else '0'

def calculate_hash(text):
    """计算拼音hash值（简单实现）"""
    result = 0
    for char in text:
        result = result * 31 + ord(char)
    return str(result & 0x7FFFFFFF)

def add_missing_words(entries, existing_words, char_freq, word_freq, pinyin_converter):
    """添加词频表中存在但pinyin.txt中缺失的词条"""
    print("\n正在检查缺失的词条...")

    added_count = 0

    # 检查单字
    for char, rank in char_freq.items():
        if char not in existing_words and rank < 5000:  # 只添加前5000的常用字
            if pinyin_converter:
                try:
                    pinyin = pinyin_converter.get_pinyin(char, splitter='', tone_marks='none')
                    if pinyin:
                        shortcut = calculate_shortcut(pinyin)
                        hash_val = calculate_hash(pinyin)

                        entries.append({
                            'word': char,
                            'pinyin': pinyin,
                            'shortcut': shortcut,
                            'hash': hash_val,
                            'original_line': -1  # 标记为新添加
                        })
                        added_count += 1

                        if added_count % 100 == 0:
                            print(f"  已添加 {added_count} 个单字...")
                except:
                    pass

    print(f"  共添加 {added_count} 个缺失的常用字")

    return entries

def reorder_pinyin_file(pinyin_file, csv_file, output_file):
    """重新排序 pinyin.txt 文件"""

    # 加载词频数据
    char_freq, word_freq = load_frequency_data(csv_file)

    # 加载拼音数据
    entries, existing_words, pinyin_converter = load_pinyin_data(pinyin_file)

    # 添加缺失的词条
    if pinyin_converter:
        entries = add_missing_words(entries, existing_words, char_freq, word_freq, pinyin_converter)

    # 计算频率分数
    print("\n正在计算频率分数...")
    for i, entry in enumerate(entries):
        entry['freq_score'] = get_word_frequency_score(entry['word'], char_freq, word_freq)

        if (i + 1) % 100000 == 0:
            print(f"  已处理 {i + 1} 条...")

    print("正在排序...")
    # 排序规则：
    # 1. 按频率分数排序（分数越小越靠前）
    # 2. 相同分数时，按词长排序（短词优先）
    # 3. 相同词长时，保持原有顺序
    entries.sort(key=lambda x: (x['freq_score'], len(x['word']), x['original_line'] if x['original_line'] > 0 else 999999999))

    print("正在写入新文件...")
    with open(output_file, 'w', encoding='utf-8') as f:
        for entry in entries:
            f.write(f"{entry['word']}\t{entry['pinyin']}\t{entry['shortcut']}\t{entry['hash']}\n")

    print(f"完成！新文件已保存到: {output_file}")

    # 显示前100个词条
    print("\n前100个词条预览：")
    for i, entry in enumerate(entries[:100], 1):
        marker = "★" if entry['original_line'] == -1 else " "
        print(f"{i:3d}. {marker} {entry['word']:8s} {entry['pinyin']:20s} (分数: {entry['freq_score']:6d})")

    # 显示一些关键字的排名
    print("\n关键字排名检查：")
    key_words = ['的', '我', '窝', '握', '卧', '沃', '涡', '蜗', '很', '红', '亮', '两', '良', '量']
    for word in key_words:
        for i, entry in enumerate(entries, 1):
            if entry['word'] == word:
                print(f"  {word}: 第 {i} 位 (分数: {entry['freq_score']})")
                break

    # 显示 wo 相关字的排名
    print("\n拼音为 'wo' 的字排名（前20个）：")
    wo_chars = []
    for i, entry in enumerate(entries, 1):
        if entry['pinyin'] == 'wo' and len(entry['word']) == 1:
            wo_chars.append((i, entry['word'], entry['freq_score']))
            if len(wo_chars) >= 20:
                break
    for rank, char, score in wo_chars:
        print(f"  {char}: 第 {rank} 位 (分数: {score})")

def main():
    pinyin_file = 'Sources/Preparing/Resources/pinyin.txt'
    csv_file = '../现代汉语语料库分词类词频表.csv'
    output_file = 'Sources/Preparing/Resources/pinyin_reordered.txt'

    if len(sys.argv) > 1:
        csv_file = sys.argv[1]
    if len(sys.argv) > 2:
        pinyin_file = sys.argv[2]
    if len(sys.argv) > 3:
        output_file = sys.argv[3]

    print("=" * 80)
    print("基于现代汉语语料库词频表的拼音排序工具")
    print("=" * 80)
    print(f"词频文件: {csv_file}")
    print(f"拼音文件: {pinyin_file}")
    print(f"输出文件: {output_file}")
    print()

    try:
        reorder_pinyin_file(pinyin_file, csv_file, output_file)
        print("\n排序完成！")
        print(f"\n下一步操作：")
        print(f"1. 检查新文件: {output_file}")
        print(f"2. 如果满意，替换原文件:")
        print(f"   mv {output_file} {pinyin_file}")
        print(f"3. 重新构建数据库:")
        print(f"   cd Preparing && swift run -c release")
        print(f"4. 重新编译应用:")
        print(f"   ./rebuild.sh")
    except Exception as e:
        print(f"\n错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
