#!/usr/bin/env python3
"""
删除 pinyin.txt 中无法正常显示的生僻字
保留常用字和可以正常显示的字符
"""

import sys
import unicodedata

def is_displayable_char(char):
    """
    判断字符是否可以正常显示
    """
    # 基本汉字范围 (CJK Unified Ideographs)
    if '\u4e00' <= char <= '\u9fff':
        return True

    # CJK扩展A区 (一些常用字)
    if '\u3400' <= char <= '\u4dbf':
        return True

    # 其他可显示字符（字母、数字、标点等）
    if char.isascii() or char in '，。！？；：""''（）【】《》、':
        return True

    return False

def is_valid_word(word):
    """
    判断词条是否有效（所有字符都可以正常显示）
    """
    if not word:
        return False

    # 检查每个字符
    for char in word:
        if not is_displayable_char(char):
            return False

    return True

def clean_pinyin_file(input_file, output_file):
    """
    清理 pinyin.txt 文件，删除生僻字
    """
    print(f"正在读取文件: {input_file}")

    valid_entries = []
    removed_entries = []

    with open(input_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) != 4:
                print(f"警告: 第 {line_num} 行格式不正确，跳过")
                continue

            word, pinyin, shortcut, hash_val = parts

            # 检查词条是否有效
            if is_valid_word(word):
                valid_entries.append(line)
            else:
                removed_entries.append((line_num, word, pinyin))

            if line_num % 100000 == 0:
                print(f"已处理 {line_num} 行...")

    print(f"\n统计信息:")
    print(f"  总词条数: {len(valid_entries) + len(removed_entries)}")
    print(f"  保留词条: {len(valid_entries)}")
    print(f"  删除词条: {len(removed_entries)}")

    # 显示一些被删除的词条示例
    if removed_entries:
        print(f"\n删除的词条示例（前50个）:")
        for i, (line_num, word, pinyin) in enumerate(removed_entries[:50], 1):
            # 尝试显示字符的Unicode信息
            char_info = []
            for char in word:
                try:
                    name = unicodedata.name(char, 'UNKNOWN')
                    char_info.append(f"U+{ord(char):04X}")
                except:
                    char_info.append(f"U+{ord(char):04X}")

            print(f"  {i:3d}. 行{line_num:7d}: {word:10s} ({pinyin:15s}) - {', '.join(char_info)}")

    # 写入清理后的文件
    print(f"\n正在写入清理后的文件: {output_file}")
    with open(output_file, 'w', encoding='utf-8') as f:
        for line in valid_entries:
            f.write(line + '\n')

    print(f"完成！")

    return len(valid_entries), len(removed_entries)

def main():
    input_file = 'Sources/Preparing/Resources/pinyin.txt'
    output_file = 'Sources/Preparing/Resources/pinyin_cleaned.txt'

    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]

    print("=" * 80)
    print("拼音词库生僻字清理工具")
    print("=" * 80)
    print(f"输入文件: {input_file}")
    print(f"输出文件: {output_file}")
    print()

    try:
        valid_count, removed_count = clean_pinyin_file(input_file, output_file)

        print(f"\n清理完成！")
        print(f"保留了 {valid_count} 条词条")
        print(f"删除了 {removed_count} 条生僻字词条")
        print(f"删除比例: {removed_count / (valid_count + removed_count) * 100:.2f}%")

        print(f"\n下一步操作：")
        print(f"1. 检查清理后的文件: {output_file}")
        print(f"2. 如果满意，替换原文件:")
        print(f"   mv {output_file} {input_file}")
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
