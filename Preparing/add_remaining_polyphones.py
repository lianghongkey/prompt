#!/usr/bin/env python3
"""
Add remaining important polyphones that are missing
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

# Additional important polyphones that might be missing
additional_polyphones = [
    # Common ones that might be missing
    ("长", "chang"),    # 长度 vs 长大
    ("长", "zhang"),    # 长大 vs 长度
    ("重", "chong"),    # 重复 vs 重量
    ("重", "zhong"),    # 重量 vs 重复
    ("处", "chu"),      # 处理 vs 到处
    ("处", "chu"),      # 到处 vs 处理
    ("当", "dang"),     # 当时 vs 当铺
    ("当", "dang"),     # 当铺 vs 当时
    ("倒", "dao"),      # 倒下 vs 倒车
    ("倒", "dao"),      # 倒车 vs 倒下
    ("分", "fen"),      # 分开 vs 分外
    ("分", "fen"),      # 分外 vs 分开
    ("更", "geng"),     # 更加 vs 更改
    ("更", "geng"),     # 更改 vs 更加
    ("供", "gong"),     # 供给 vs 供品
    ("供", "gong"),     # 供品 vs 供给
    ("冠", "guan"),     # 冠军 vs 衣冠
    ("冠", "guan"),     # 衣冠 vs 冠军
    ("间", "jian"),     # 中间 vs 间隔
    ("间", "jian"),     # 间隔 vs 中间
    ("将", "jiang"),    # 将来 vs 将军
    ("将", "jiang"),    # 将军 vs 将来
    ("教", "jiao"),     # 教书 vs 教育
    ("教", "jiao"),     # 教育 vs 教书
    ("禁", "jin"),      # 禁止 vs 不禁
    ("禁", "jin"),      # 不禁 vs 禁止
    ("尽", "jin"),      # 尽力 vs 尽管
    ("尽", "jin"),      # 尽管 vs 尽力
    ("卷", "juan"),     # 卷子 vs 卷起
    ("卷", "juan"),     # 卷起 vs 卷子
    ("看", "kan"),      # 看见 vs 看守
    ("看", "kan"),      # 看守 vs 看见
    ("空", "kong"),     # 空间 vs 空白
    ("空", "kong"),     # 空白 vs 空间
    ("累", "lei"),      # 累计 vs 疲累
    ("累", "lei"),      # 疲累 vs 累赘
    ("量", "liang"),    # 数量 vs 量体裁衣
    ("量", "liang"),    # 量体裁衣 vs 数量
    ("笼", "long"),     # 笼子 vs 笼罩
    ("笼", "long"),     # 笼罩 vs 笼子
    ("露", "lou"),      # 露出 vs 露水
    ("露", "lu"),       # 露水 vs 露出
    ("蒙", "meng"),     # 蒙骗 vs 启蒙
    ("蒙", "meng"),     # 启蒙 vs 蒙古
    ("磨", "mo"),       # 磨练 vs 磨坊
    ("磨", "mo"),       # 磨坊 vs 磨练
    ("难", "nan"),      # 困难 vs 灾难
    ("难", "nan"),      # 灾难 vs 困难
    ("宁", "ning"),     # 宁静 vs 宁可
    ("宁", "ning"),     # 宁可 vs 宁静
    ("泊", "bo"),       # 停泊 vs 湖泊
    ("泊", "po"),       # 湖泊 vs 停泊
    ("迫", "pai"),      # 迫击炮 vs 迫使
    ("迫", "po"),       # 迫使 vs 迫击炮
    ("铺", "pu"),       # 铺路 vs 店铺
    ("铺", "pu"),       # 店铺 vs 铺路
    ("曲", "qu"),       # 弯曲 vs 曲子
    ("曲", "qu"),       # 曲子 vs 弯曲
    ("散", "san"),      # 分散 vs 散步
    ("散", "san"),      # 散步 vs 分散
    ("丧", "sang"),     # 丧失 vs 丧事
    ("丧", "sang"),     # 丧事 vs 丧失
    ("少", "shao"),     # 少年 vs 多少
    ("少", "shao"),     # 多少 vs 少年
    ("舍", "she"),      # 舍弃 vs 宿舍
    ("舍", "she"),      # 宿舍 vs 舍弃
    ("什", "shen"),     # 什么 vs 什锦
    ("什", "shi"),      # 什锦 vs 什么
    ("挑", "tiao"),     # 挑选 vs 挑战
    ("挑", "tiao"),     # 挑战 vs 挑选
    ("为", "wei"),      # 为了 vs 因为
    ("为", "wei"),      # 因为 vs 作为
    ("鲜", "xian"),     # 新鲜 vs 鲜见
    ("鲜", "xian"),     # 鲜见 vs 新鲜
    ("相", "xiang"),    # 相同 vs 相貌
    ("相", "xiang"),    # 相貌 vs 相同
    ("兴", "xing"),     # 兴奋 vs 高兴
    ("兴", "xing"),     # 高兴 vs 兴奋
    ("要", "yao"),      # 要求 vs 重要
    ("要", "yao"),      # 重要 vs 要求
    ("应", "ying"),     # 应该 vs 答应
    ("应", "ying"),     # 答应 vs 应该
    ("载", "zai"),      # 记载 vs 装载
    ("载", "zai"),      # 装载 vs 记载
    ("涨", "zhang"),    # 涨价 vs 涨潮
    ("涨", "zhang"),    # 涨潮 vs 涨价
    ("中", "zhong"),    # 中间 vs 中奖
    ("中", "zhong"),    # 中奖 vs 中间
    ("种", "zhong"),    # 种子 vs 种植
    ("种", "zhong"),    # 种植 vs 种子
    ("转", "zhuan"),    # 转动 vs 转身
    ("转", "zhuan"),    # 转身 vs 转动
    ("钻", "zuan"),     # 钻研 vs 钻石
    ("钻", "zuan"),     # 钻石 vs 钻研
    ("作", "zuo"),      # 作业 vs 作坊
    ("作", "zuo"),      # 作坊 vs 作业

    # Additional important ones
    ("背", "bei"),      # 背包 vs 背叛
    ("背", "bei"),      # 背叛 vs 背包
    ("奔", "ben"),      # 奔跑 vs 投奔
    ("奔", "ben"),      # 投奔 vs 奔跑
    ("藏", "cang"),     # 躲藏 vs 宝藏
    ("藏", "zang"),     # 宝藏 vs 躲藏
    ("场", "chang"),    # 场地 vs 打场
    ("场", "chang"),    # 打场 vs 场地
    ("称", "chen"),     # 称呼 vs 对称
    ("称", "cheng"),    # 对称 vs 称呼
    ("乘", "cheng"),    # 乘坐 vs 千乘之国
    ("乘", "sheng"),    # 千乘之国 vs 乘坐
    ("冲", "chong"),    # 冲锋 vs 冲床
    ("冲", "chong"),    # 冲床 vs 冲锋
    ("创", "chuang"),   # 创造 vs 创伤
    ("创", "chuang"),   # 创伤 vs 创造
    ("答", "da"),       # 回答 vs 答应
    ("答", "da"),       # 答应 vs 回答
    ("都", "dou"),      # 都是 vs 首都
    ("都", "dou"),      # 首都 vs 都是
    ("发", "fa"),       # 发现 vs 头发
    ("发", "fa"),       # 头发 vs 发现
    ("坊", "fang"),     # 作坊 vs 街坊
    ("坊", "fang"),     # 街坊 vs 作坊
    ("缝", "feng"),     # 缝合 vs 缝隙
    ("缝", "feng"),     # 缝隙 vs 缝合
    ("杆", "gan"),      # 杆子 vs 旗杆
    ("杆", "gan"),      # 旗杆 vs 杆子
    ("骨", "gu"),       # 骨头 vs 骨朵
    ("骨", "gu"),       # 骨朵 vs 骨头
    ("哈", "ha"),       # 哈哈 vs 哈达
    ("哈", "ha"),       # 哈达 vs 哈哈
    ("号", "hao"),      # 号码 vs 号叫
    ("号", "hao"),      # 号叫 vs 号码
    ("喝", "he"),       # 喝水 vs 喝彩
    ("喝", "he"),       # 喝彩 vs 喝水
    ("横", "heng"),     # 横行 vs 蛮横
    ("横", "heng"),     # 蛮横 vs 横行
    ("划", "hua"),      # 划船 vs 计划
    ("划", "hua"),      # 计划 vs 划船
    ("华", "hua"),      # 华丽 vs 华山
    ("华", "hua"),      # 华山 vs 华丽
    ("晃", "huang"),    # 晃动 vs 明晃晃
    ("晃", "huang"),    # 明晃晃 vs 晃动
    ("混", "hun"),      # 混合 vs 混水摸鱼
    ("混", "hun"),      # 混水摸鱼 vs 混合
    ("几", "ji"),       # 几个 vs 茶几
    ("几", "ji"),       # 茶几 vs 几个
    ("济", "ji"),       # 济南 vs 救济
    ("济", "ji"),       # 救济 vs 济南
    ("夹", "jia"),      # 夹子 vs 夹杂
    ("夹", "jia"),      # 夹杂 vs 夹子
    ("假", "jia"),      # 假如 vs 假期
    ("假", "jia"),      # 假期 vs 假如
    ("勾", "gou"),      # 勾结 vs 勾当
    ("勾", "gou"),      # 勾当 vs 勾结
    ("过", "guo"),      # 过去 vs 姓过
    ("过", "guo"),      # 姓过 vs 过去
    ("吭", "hang"),     # 吭声 vs 引吭
    ("吭", "keng"),     # 引吭 vs 吭声
    ("巷", "hang"),     # 巷道 vs 街巷
    ("巷", "xiang"),    # 街巷 vs 巷道
    ("弹", "dan"),      # 子弹 vs 弹性
    ("弹", "tan"),      # 弹性 vs 子弹
    ("帖", "tie"),      # 字帖 vs 请帖
    ("帖", "tie"),      # 请帖 vs 字帖
]

def main():
    pinyin_file = "Sources/Preparing/Resources/pinyin.txt"

    # Read existing file
    with open(pinyin_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Parse existing entries
    existing_entries = set()
    for line in lines:
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            char, pinyin = parts[0], parts[1]
            existing_entries.add((char, pinyin))

    # Find entries to add
    entries_to_add = []
    for char, pinyin in additional_polyphones:
        if (char, pinyin) not in existing_entries:
            shortcut = get_intercode(pinyin[0])
            if shortcut is None:
                print(f"Warning: Cannot calculate shortcut for '{pinyin}' (char: {char})")
                continue
            ping = deterministic_hash(pinyin)
            entry = f"{char}\t{pinyin}\t{shortcut}\t{ping}\n"
            entries_to_add.append((char, entry))
            print(f"Will add: {char} {pinyin}")

    if not entries_to_add:
        print("\nNo new entries to add!")
        return

    # Insert new entries
    new_lines = []
    added_for_char = {}

    for line in lines:
        new_lines.append(line)
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            char = parts[0]
            if char not in added_for_char:
                char_entries = [entry for add_char, entry in entries_to_add if add_char == char]
                if char_entries:
                    new_lines.extend(char_entries)
                    added_for_char[char] = True

    # Write back
    with open(pinyin_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

    print(f"\nAdded {len(added_for_char)} characters with additional polyphone entries!")
    print(f"Total new entries: {len([e for c, e in entries_to_add if c in added_for_char])}")
    print("\nPlease rebuild the database with: cd Preparing && swift run -c release")

if __name__ == "__main__":
    main()
