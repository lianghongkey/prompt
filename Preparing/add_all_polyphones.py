#!/usr/bin/env python3
"""
Add comprehensive polyphone (多音字) entries to pinyin.txt
This script includes a comprehensive list of common Chinese polyphones
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

# Comprehensive list of Chinese polyphones (多音字)
# Format: (character, pinyin, example usage)
polyphones_to_add = [
    # A
    ("阿", "e"),        # 阿姨 vs 阿谀

    # B
    ("扒", "pa"),       # 扒手 vs 扒开
    ("薄", "bao"),      # 薄饼
    ("薄", "bo"),       # 薄弱
    ("背", "bei"),      # 背包 vs 背叛
    ("奔", "ben"),      # 奔跑 vs 投奔
    ("辟", "pi"),       # 开辟 vs 复辟
    ("便", "pian"),     # 便宜 vs 方便
    ("扁", "pian"),     # 扁舟 vs 扁平
    ("泊", "po"),       # 湖泊 vs 停泊
    ("剥", "bao"),      # 剥削 vs 剥皮

    # C
    ("藏", "zang"),     # 宝藏 vs 躲藏
    ("曾", "zeng"),     # 曾孙 vs 曾经
    ("差", "cha"),      # 差别
    ("差", "chai"),     # 出差
    ("差", "ci"),       # 参差
    ("禅", "shan"),     # 禅让 vs 禅师
    ("颤", "zhan"),     # 颤动 vs 颤抖
    ("场", "chang"),    # 场地 vs 打场
    ("朝", "zhao"),     # 朝代 vs 朝向
    ("车", "ju"),       # 象棋车 vs 车马
    ("称", "cheng"),    # 对称 vs 称呼
    ("澄", "deng"),     # 澄清 vs 澄澈
    ("乘", "sheng"),    # 千乘之国 vs 乘坐
    ("冲", "chong"),    # 冲锋 vs 冲床
    ("臭", "xiu"),      # 乳臭未干 vs 臭味
    ("处", "chu"),      # 处理 vs 到处
    ("畜", "xu"),       # 牲畜 vs 畜牧
    ("创", "chuang"),   # 创造 vs 创伤
    ("绰", "chuo"),     # 绰号 vs 宽绰
    ("伺", "si"),       # 伺机 vs 伺候
    ("枞", "zong"),     # 枞阳 vs 枞树
    ("攒", "zan"),      # 攒动 vs 攒钱

    # D
    ("答", "da"),       # 回答 vs 答应
    ("大", "dai"),      # 大夫 vs 大小
    ("逮", "dai"),      # 逮捕 vs 逮住
    ("单", "dan"),      # 单独
    ("单", "shan"),     # 单县
    ("单", "chan"),     # 单于
    ("当", "dang"),     # 当时 vs 当铺
    ("倒", "dao"),      # 倒下 vs 倒车
    ("得", "de"),       # 得到
    ("得", "dei"),      # 得亏
    ("的", "di"),       # 的确 vs 目的
    ("地", "de"),       # 地道 vs 土地
    ("调", "tiao"),     # 调子 vs 调动
    ("丁", "zheng"),    # 丁丁 vs 姓丁
    ("都", "dou"),      # 都是 vs 首都
    ("度", "duo"),      # 揣度 vs 度量
    ("囤", "tun"),      # 粮囤 vs 囤积

    # E
    ("恶", "e"),        # 恶心 vs 凶恶
    ("恶", "wu"),       # 可恶 vs 厌恶

    # F
    ("发", "fa"),       # 发现 vs 头发
    ("坊", "fang"),     # 作坊 vs 街坊
    ("分", "fen"),      # 分开 vs 分外
    ("缝", "feng"),     # 缝合 vs 缝隙
    ("佛", "fu"),       # 仿佛 vs 佛教
    ("夫", "fu"),       # 夫人 vs 大夫

    # G
    ("杆", "gan"),      # 杆子 vs 旗杆
    ("杠", "gang"),     # 杠杆 vs 抬杠
    ("膏", "gao"),      # 膏药 vs 牙膏
    ("革", "ji"),       # 皮革 vs 革命
    ("葛", "ge"),       # 葛根 vs 姓葛
    ("给", "gei"),      # 给你
    ("给", "ji"),       # 给予
    ("更", "geng"),     # 更加 vs 更改
    ("供", "gong"),     # 供给 vs 供品
    ("勾", "gou"),      # 勾结 vs 勾当
    ("骨", "gu"),       # 骨头 vs 骨朵
    ("谷", "yu"),       # 吐谷浑 vs 谷物
    ("冠", "guan"),     # 冠军 vs 衣冠
    ("龟", "jun"),      # 龟裂 vs 乌龟
    ("龟", "qiu"),      # 龟兹
    ("过", "guo"),      # 过去 vs 姓过

    # H
    ("哈", "ha"),       # 哈哈 vs 哈达
    ("还", "hai"),      # 还是
    ("还", "huan"),     # 还书
    ("巷", "xiang"),    # 街巷 vs 巷道
    ("吭", "keng"),     # 引吭 vs 吭声
    ("号", "hao"),      # 号码 vs 号叫
    ("喝", "he"),       # 喝水 vs 喝彩
    ("和", "he"),       # 和平
    ("和", "huo"),      # 和面
    ("和", "hu"),       # 和牌
    ("横", "heng"),     # 横行 vs 蛮横
    ("哄", "hong"),     # 哄骗
    ("哄", "hong"),     # 哄堂大笑
    ("哄", "hong"),     # 起哄
    ("划", "hua"),      # 划船 vs 计划
    ("华", "hua"),      # 华丽 vs 华山
    ("晃", "huang"),    # 晃动 vs 明晃晃
    ("会", "kuai"),     # 会计 vs 会议
    ("混", "hun"),      # 混合 vs 混水摸鱼

    # J
    ("几", "ji"),       # 几个 vs 茶几
    ("济", "ji"),       # 济南 vs 救济
    ("系", "ji"),       # 系统 vs 关系
    ("夹", "jia"),      # 夹子 vs 夹杂
    ("假", "jia"),      # 假如 vs 假期
    ("间", "jian"),     # 中间 vs 间隔
    ("将", "jiang"),    # 将来 vs 将军
    ("嚼", "jiao"),     # 嚼舌 vs 咀嚼
    ("角", "jue"),      # 角色 vs 角度
    ("觉", "jiao"),     # 睡觉
    ("觉", "jue"),      # 感觉
    ("教", "jiao"),     # 教书 vs 教育
    ("校", "jiao"),     # 校对 vs 学校
    ("解", "jie"),      # 解决
    ("解", "xie"),      # 解送
    ("解", "jie"),      # 押解
    ("禁", "jin"),      # 禁止 vs 不禁
    ("劲", "jing"),     # 使劲 vs 劲头
    ("尽", "jin"),      # 尽力 vs 尽管
    ("茎", "jing"),     # 茎叶 vs 根茎
    ("颈", "geng"),     # 脖颈 vs 颈项
    ("卷", "juan"),     # 卷子 vs 卷起
    ("嚼", "jue"),      # 咀嚼 vs 嚼舌

    # K
    ("卡", "ka"),       # 卡片 vs 关卡
    ("卡", "qia"),      # 卡住
    ("看", "kan"),      # 看见 vs 看守
    ("壳", "qiao"),     # 地壳 vs 贝壳
    ("空", "kong"),     # 空间 vs 空白

    # L
    ("蓝", "lan"),      # 蓝色 vs 蓝田
    ("烙", "lao"),      # 烙印 vs 烙饼
    ("勒", "lei"),      # 勒索 vs 勒紧
    ("了", "le"),       # 完了
    ("了", "liao"),     # 了解
    ("累", "lei"),      # 累计 vs 疲累
    ("累", "lei"),      # 疲累 vs 累赘
    ("擂", "lei"),      # 擂台 vs 擂鼓
    ("蠡", "li"),       # 蠡县 vs 管窥蠡测
    ("俩", "lia"),      # 俩人 vs 伊俩
    ("量", "liang"),    # 数量 vs 量体裁衣
    ("踉", "liang"),    # 踉跄 vs 跳踉
    ("咧", "lie"),      # 咧嘴 vs 大大咧咧
    ("淋", "lin"),      # 淋雨 vs 淋漓
    ("溜", "liu"),      # 溜走 vs 溜达
    ("笼", "long"),     # 笼子 vs 笼罩
    ("露", "lu"),       # 露水 vs 露出
    ("绿", "lu"),       # 绿色 vs 绿林
    ("落", "luo"),      # 落下 vs 落后
    ("落", "la"),       # 丢三落四
    ("落", "lao"),      # 落枕

    # M
    ("脉", "mo"),       # 山脉 vs 脉搏
    ("埋", "man"),      # 埋怨 vs 埋葬
    ("蔓", "wan"),      # 瓜蔓 vs 蔓延
    ("氓", "meng"),     # 氓隶 vs 流氓
    ("蒙", "meng"),     # 蒙骗 vs 启蒙
    ("蒙", "meng"),     # 启蒙 vs 蒙古
    ("蒙", "meng"),     # 蒙古
    ("靡", "mi"),       # 靡费 vs 委靡
    ("秘", "bi"),       # 秘鲁 vs 秘密
    ("泌", "mi"),       # 分泌 vs 泌阳
    ("模", "mu"),       # 模样 vs 模型
    ("抹", "mo"),       # 抹杀 vs 抹布
    ("抹", "ma"),       # 抹布
    ("没", "mei"),      # 没有
    ("没", "mo"),       # 没收
    ("摩", "mo"),       # 摩擦 vs 摩登
    ("磨", "mo"),       # 磨练 vs 磨坊

    # N
    ("难", "nan"),      # 困难 vs 灾难
    ("难", "nuo"),      # 刁难
    ("宁", "ning"),     # 宁静 vs 宁可
    ("宁", "ning"),     # 宁可
    ("弄", "long"),     # 弄堂 vs 玩弄

    # P
    ("排", "pai"),      # 排列 vs 排场
    ("迫", "po"),       # 迫使 vs 迫击炮
    ("泮", "pan"),      # 泮宫 vs 泮池
    ("刨", "bao"),      # 刨根问底 vs 刨子
    ("炮", "pao"),      # 大炮 vs 炮制
    ("炮", "bao"),      # 炮制
    ("喷", "pen"),      # 喷射 vs 喷香
    ("片", "pian"),     # 片刻 vs 照片
    ("漂", "piao"),     # 漂浮 vs 漂亮
    ("漂", "piao"),     # 漂亮
    ("撇", "pie"),      # 撇开 vs 撇嘴
    ("瓶", "ping"),     # 瓶子 vs 花瓶
    ("仆", "pu"),       # 仆人 vs 前仆后继
    ("铺", "pu"),       # 铺路 vs 店铺
    ("铺", "pu"),       # 店铺
    ("曝", "pu"),       # 曝光 vs 一曝十寒

    # Q
    ("栖", "xi"),       # 两栖 vs 栖息
    ("蹊", "xi"),       # 蹊径 vs 蹊跷
    ("荨", "xun"),      # 荨麻疹 vs 荨麻
    ("强", "qiang"),    # 强大
    ("强", "jiang"),    # 倔强
    ("强", "qiang"),    # 勉强
    ("悄", "qiao"),     # 悄悄 vs 悄然
    ("翘", "qiao"),     # 翘起 vs 翘楚
    ("切", "qie"),      # 切实 vs 一切
    ("亲", "qing"),     # 亲家 vs 亲人
    ("曲", "qu"),       # 弯曲 vs 曲子
    ("雀", "qiao"),     # 麻雀 vs 雀跃
    ("圈", "juan"),     # 猪圈 vs 圆圈

    # R
    ("任", "ren"),      # 任务 vs 姓任

    # S
    ("塞", "sai"),      # 塞子
    ("塞", "se"),       # 堵塞
    ("塞", "sai"),      # 边塞
    ("散", "san"),      # 分散 vs 散步
    ("丧", "sang"),     # 丧失 vs 丧事
    ("色", "shai"),     # 色子 vs 颜色
    ("厦", "sha"),      # 大厦 vs 厦门
    ("煞", "sha"),      # 煞费苦心 vs 煞白
    ("杉", "sha"),      # 杉木 vs 杉树
    ("苫", "shan"),     # 苫布 vs 草苫
    ("扇", "shan"),     # 扇子 vs 扇动
    ("少", "shao"),     # 少年 vs 多少
    ("舍", "she"),      # 舍弃 vs 宿舍
    ("什", "shi"),      # 什锦 vs 什么
    ("葚", "ren"),      # 葚子 vs 桑葚
    ("识", "zhi"),      # 标识 vs 认识
    ("似", "si"),       # 似乎
    ("似", "shi"),      # 似的
    ("宿", "su"),       # 宿舍
    ("宿", "xiu"),      # 星宿
    ("宿", "su"),       # 一宿
    ("率", "lu"),       # 效率 vs 率领
    ("说", "shuo"),     # 说话
    ("说", "shui"),     # 说服
    ("说", "yue"),      # 游说
    ("数", "shu"),      # 数学
    ("数", "shu"),      # 数数
    ("数", "shuo"),     # 数见不鲜
    ("遂", "sui"),      # 遂心 vs 半身不遂

    # T
    ("沓", "da"),       # 一沓 vs 杂沓
    ("挞", "ta"),       # 鞭挞 vs 挞伐
    ("拓", "tuo"),      # 开拓 vs 拓片
    ("弹", "dan"),      # 子弹 vs 弹性
    ("挑", "tiao"),     # 挑选 vs 挑战
    ("调", "tiao"),     # 调整 vs 调子
    ("帖", "tie"),      # 字帖 vs 请帖
    ("帖", "tie"),      # 请帖
    ("通", "tong"),     # 通过 vs 通红

    # W
    ("尾", "yi"),       # 马尾 vs 尾巴
    ("为", "wei"),      # 为了
    ("为", "wei"),      # 因为
    ("圩", "xu"),       # 圩子 vs 圩田
    ("尉", "yu"),       # 尉迟 vs 尉官
    ("喂", "wei"),      # 喂养 vs 喂食

    # X
    ("吓", "he"),       # 恐吓 vs 吓唬
    ("鲜", "xian"),     # 新鲜 vs 鲜见
    ("纤", "qian"),     # 纤夫 vs 纤维
    ("相", "xiang"),    # 相同 vs 相貌
    ("削", "xiao"),     # 削减
    ("削", "xue"),      # 剥削
    ("校", "jiao"),     # 校对 vs 学校
    ("肖", "xiao"),     # 肖像 vs 姓肖
    ("兴", "xing"),     # 兴奋 vs 高兴
    ("省", "sheng"),    # 省份
    ("省", "xing"),     # 反省
    ("宿", "xiu"),      # 一宿 vs 星宿
    ("血", "xie"),      # 流血 vs 血液
    ("熏", "xun"),      # 熏陶 vs 熏香

    # Y
    ("咽", "yan"),      # 咽喉
    ("咽", "ye"),       # 呜咽
    ("咽", "yan"),      # 吞咽
    ("燕", "yan"),      # 燕子 vs 燕国
    ("扬", "yang"),     # 扬起 vs 表扬
    ("钥", "yue"),      # 锁钥 vs 钥匙
    ("要", "yao"),      # 要求 vs 重要
    ("叶", "xie"),      # 姓叶 vs 叶子
    ("应", "ying"),     # 应该 vs 答应
    ("佣", "yong"),     # 佣金 vs 雇佣
    ("与", "yu"),       # 与其 vs 参与
    ("吁", "xu"),       # 气喘吁吁 vs 呼吁
    ("乐", "le"),       # 快乐
    ("乐", "yue"),      # 音乐
    ("晕", "yun"),      # 晕倒 vs 头晕

    # Z
    ("载", "zai"),      # 记载 vs 装载
    ("择", "zhai"),     # 择菜 vs 选择
    ("扎", "za"),       # 扎实
    ("扎", "zha"),      # 扎针
    ("扎", "zha"),      # 挣扎
    ("轧", "ya"),       # 倾轧 vs 轧钢
    ("粘", "nian"),     # 粘连 vs 粘贴
    ("涨", "zhang"),    # 涨价 vs 涨潮
    ("着", "zhao"),     # 着急
    ("着", "zhe"),      # 看着
    ("着", "zhuo"),     # 着陆
    ("折", "zhe"),      # 折断
    ("折", "she"),      # 折本
    ("折", "zhe"),      # 折腾
    ("正", "zheng"),    # 正确 vs 正月
    ("殖", "zhi"),      # 繁殖 vs 殖民
    ("中", "zhong"),    # 中间 vs 中奖
    ("种", "zhong"),    # 种子 vs 种植
    ("轴", "zhou"),     # 轴心 vs 画轴
    ("属", "zhu"),      # 属于 vs 家属
    ("爪", "zhua"),     # 爪子
    ("爪", "zhao"),     # 鹰爪
    ("转", "zhuan"),    # 转动 vs 转身
    ("传", "chuan"),    # 传说
    ("传", "zhuan"),    # 传记
    ("撞", "zhuang"),   # 撞击 vs 撞见
    ("幢", "chuang"),   # 经幢 vs 一幢
    ("缀", "zhui"),     # 点缀 vs 连缀
    ("综", "zong"),     # 综合 vs 综述
    ("钻", "zuan"),     # 钻研 vs 钻石
    ("钻", "zuan"),     # 钻石
    ("作", "zuo"),      # 作业 vs 作坊
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
            if shortcut is None:
                print(f"Warning: Cannot calculate shortcut for '{pinyin}' (char: {char})")
                continue
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
    added_for_char = {}  # Track which characters we've added entries for

    for line in lines:
        new_lines.append(line)
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            char = parts[0]
            # Check if we have entries to add for this character
            if char not in added_for_char:
                # Find all entries to add for this character
                char_entries = [entry for add_char, entry in entries_to_add if add_char == char]
                if char_entries:
                    new_lines.extend(char_entries)
                    added_for_char[char] = True

    # Write back to file
    with open(pinyin_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

    print(f"\nAdded {len(added_for_char)} characters with polyphone entries!")
    print(f"Total new entries: {len([e for c, e in entries_to_add if c in added_for_char])}")
    print("\nPlease rebuild the database with: cd Preparing && swift run -c release")

if __name__ == "__main__":
    main()
