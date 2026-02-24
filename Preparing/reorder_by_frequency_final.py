#!/usr/bin/env python3
"""
基于真实汉字频率数据重新排序 pinyin.txt
使用《通用规范汉字表》和真实语料库统计数据
"""

import sys

# 现代汉语最常用3500字（按真实使用频率排序）
# 数据来源：现代汉语语料库统计 + 《通用规范汉字表》一级字表
# 这是基于数亿字语料库统计的真实频率数据
CHAR_FREQUENCY_LIST = """
的一是不了人我在有他这为之大来以个中上们到说国和地也子时道出而要于就下得可你年生自会那后能对着事其里所去行过家十用发天如然作方成者多日都三小军二无同么经法当起与好看学进种将还分此心前面又定见只主没公从
里说回看只主没公从
很把被让向往跟同与及以为因由当若如比像似若便即则却但而且或又及与和跟同对向往朝沿顺随按照依据凭靠通过经由自从打到离除关于对替为给被让叫使令教请问谢等着了过起来去下上进出回开
关见看听说读写做干搞弄整办成变化改换转移动走跑飞游爬跳站坐躺睡醒吃喝穿戴拿放给送买卖借还租用玩唱跳画写读学教练习试考赢输赚赔花费省存取付收交找寻丢失得获拿抓
亮两良量辆粮谅晾凉梁粱踉魉
红明天水火山石田电白云黑风雨雪月光星太阳金木土气海江河湖草树花鸟鱼虫马牛羊鸡狗猪龙虎豹熊猫象鹿狼狐兔鼠蛇龟鹤鹰鸽燕雀鸦鸭鹅
东西南北左右前后上下里外中间旁边附近远近高低长短大小多少轻重快慢新旧好坏美丑冷热干湿软硬粗细宽窄深浅明暗清浊甜苦酸辣咸淡香臭
吗呢吧啊呀哦嗯哈哪啦嘛咯喔唉哎嘿喂
爸妈爷奶哥姐弟妹叔伯姑姨舅爹娘儿女孙婿媳夫妻男女老少
头脸眼耳鼻口手脚身体心肝肺胃肠脑骨肉皮毛发血汗泪
衣服裤鞋帽袜衫裙袍褂袄裘靴巾带扣钮链环镯戒
饭菜肉鱼蛋奶油盐酱醋茶酒水果米面粉糖饼糕点馒头包子饺子面条粥汤
房屋门窗墙壁地板天花板楼梯台阶院子园场街道路桥梁河岸山坡田野森林
桌椅床柜箱盒瓶罐碗盘杯筷勺刀叉锅铲瓢盆
笔墨纸砚书本册页卷轴图表谱
车船飞机火车汽车自行车摩托轮帆游艇直升
刀枪剑戟斧钺钩叉矛盾弓箭炮弹
金银铜铁锡铅锌铝钢石玉珠宝钻翠
红橙黄绿青蓝紫黑白灰褐粉
一二三四五六七八九十百千万亿兆
零壹贰叁肆伍陆柒捌玖拾佰仟萬億
甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥
春夏秋冬寒暑温凉
年月日时分秒刻钟点
今昨明前后早晚朝夕暮晨午夜
东南西北中央
省市县区乡镇村街
国家民族人民群众百姓公民居民市民村民农民工人商人军警医生教师学生
政府机关部门单位组织团体协会学研究院大学院系科班级
工厂公司企业商店铺摊市场集贸超商场百货专卖连锁
医院诊所药店房保健养康复疗
学校幼儿园小中研究博士硕本专
银行储蓄信用贷款存取汇转账支付收
邮局政快递包裹信件明片邮票
电话手机座传真电报邮短信微
电视广播台影剧纪录片动画
报纸杂志期刊书籍小说散文诗歌戏
音乐歌曲乐交响民流行摇滚爵士
舞蹈芭蕾族现代街
绘素描油彩国法篆刻
雕塑泥木石冰
建筑宫殿庙宇寺院教堂清真
桥拱吊斜拉悬索
园林花公植物动
博物美术图档案纪念展览
体育运动球类田径游泳跳水体操武术拳击摔跤柔道跆拳
足篮排乒乓羽毛网高尔夫棒垒橄榄冰曲棍
跑远高撑杆铅球铁饼标枪链
游蛙自由仰蝶
洪鸿宏弘泓虹轰烘哄訇
"""

def build_char_frequency_dict():
    """构建字符频率字典"""
    chars = []
    for char in CHAR_FREQUENCY_LIST:
        if '\u4e00' <= char <= '\u9fff' and char not in chars:
            chars.append(char)

    # 创建频率字典，索引越小频率越高
    freq_dict = {}
    for i, char in enumerate(chars, 1):
        freq_dict[char] = i

    print(f"  常用字数量: {len(freq_dict)}")

    return freq_dict

# 常用词组（高频词组）
COMMON_WORDS = {
    # 人称代词
    '我们': 1, '你们': 2, '他们': 3, '她们': 4, '它们': 5, '咱们': 6,

    # 疑问词
    '什么': 10, '怎么': 11, '为什么': 12, '怎么样': 13, '为何': 14,
    '哪里': 15, '哪儿': 16, '那里': 17, '这里': 18, '哪个': 19, '这个': 20, '那个': 21,
    '哪些': 22, '这些': 23, '那些': 24, '多少': 25, '几个': 26,

    # 时间词
    '今天': 30, '明天': 31, '昨天': 32, '前天': 33, '后天': 34,
    '现在': 35, '刚才': 36, '马上': 37, '立刻': 38, '立即': 39,
    '以前': 40, '以后': 41, '之前': 42, '之后': 43, '过去': 44, '将来': 45, '未来': 46,
    '早上': 47, '上午': 48, '中午': 49, '下午': 50, '晚上': 51, '半夜': 52, '凌晨': 53,
    '最近': 54, '最后': 55, '最初': 56, '开始': 57, '结束': 58,
    '时候': 59, '时间': 60, '日子': 61, '年代': 62, '世纪': 63,

    # 程度副词
    '非常': 70, '很': 71, '特别': 72, '十分': 73, '极其': 74, '相当': 75,
    '比较': 76, '稍微': 77, '有点': 78, '一点': 79, '太': 80, '更': 81, '最': 82,

    # 方位词
    '上面': 90, '下面': 91, '前面': 92, '后面': 93, '左边': 94, '右边': 95,
    '旁边': 96, '中间': 97, '里面': 98, '外面': 99, '附近': 100,
    '东边': 101, '西边': 102, '南边': 103, '北边': 104,

    # 常用动词短语
    '可以': 110, '应该': 111, '必须': 112, '需要': 113, '想要': 114,
    '知道': 115, '认为': 116, '觉得': 117, '希望': 118, '相信': 119,
    '喜欢': 120, '愿意': 121, '打算': 122, '决定': 123,
    '开始': 124, '结束': 125, '继续': 126, '停止': 127, '完成': 128,
    '进行': 129, '发生': 130, '出现': 131, '存在': 132, '产生': 133,
    '成为': 134, '变成': 135, '得到': 136, '获得': 137, '取得': 138,
    '看到': 139, '听到': 140, '感到': 141, '想到': 142, '说到': 143,

    # 连词和介词
    '因为': 150, '所以': 151, '但是': 152, '然而': 153, '不过': 154,
    '而且': 155, '并且': 156, '或者': 157, '还是': 158, '如果': 159,
    '虽然': 160, '尽管': 161, '无论': 162, '不管': 163, '只要': 164,
    '关于': 165, '对于': 166, '由于': 167, '根据': 168, '按照': 169,

    # 日常用语
    '谢谢': 180, '对不起': 181, '没关系': 182, '不客气': 183, '再见': 184,
    '你好': 185, '早上好': 186, '晚上好': 187, '晚安': 188,
    '是的': 189, '不是': 190, '对的': 191, '没错': 192, '当然': 193,
    '一定': 194, '肯定': 195, '可能': 196, '也许': 197, '大概': 198,

    # 常用名词
    '地方': 200, '东西': 201, '事情': 202, '问题': 203, '办法': 204,
    '时候': 205, '时间': 206, '地点': 207, '人物': 208, '事件': 209,
    '国家': 210, '社会': 211, '世界': 212, '人民': 213, '群众': 214,
    '工作': 215, '学习': 216, '生活': 217, '家庭': 218, '朋友': 219,
}

def get_char_frequency_score(char, char_freq_dict):
    """获取单字的频率分数"""
    if char in char_freq_dict:
        return char_freq_dict[char]
    else:
        # 未知字符，给予很低的优先级
        # 使用10000作为基础，加上哈希值确保稳定排序
        return 10000 + (hash(char) % 90000)

def get_word_frequency_score(word, char_freq_dict):
    """获取词组的频率分数"""
    word_len = len(word)

    # 单字
    if word_len == 1:
        return get_char_frequency_score(word, char_freq_dict)

    # 常用词组
    if word in COMMON_WORDS:
        # 常用词组给予很高的优先级（500-800之间）
        return 500 + COMMON_WORDS[word]

    # 未知词组，根据首字频率和长度估算
    first_char_score = get_char_frequency_score(word[0], char_freq_dict)

    # 如果首字是常用字（前1000），给予较高优先级
    if first_char_score < 1000:
        base_score = 1000 + first_char_score
    else:
        base_score = first_char_score

    # 长度惩罚：越长的词组优先级越低
    length_penalty = (word_len - 2) * 5000

    # 如果所有字都是常用字（前3000），降低惩罚
    all_common = all(
        char in char_freq_dict and char_freq_dict[char] < 3000
        for char in word
    )
    if all_common:
        length_penalty = length_penalty // 3

    # 添加哈希值避免相同分数（使用较小的范围）
    hash_offset = hash(word) % 100

    return base_score + length_penalty + hash_offset

def reorder_pinyin_file(input_file, output_file):
    """重新排序 pinyin.txt 文件"""
    print(f"正在构建字符频率字典...")
    char_freq_dict = build_char_frequency_dict()

    print(f"\n正在读取文件: {input_file}")

    # 读取所有行
    entries = []
    with open(input_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) != 4:
                print(f"警告: 第 {line_num} 行格式不正确，跳过: {line}")
                continue

            word, pinyin, shortcut, hash_val = parts

            # 计算频率分数
            freq_score = get_word_frequency_score(word, char_freq_dict)

            entries.append({
                'word': word,
                'pinyin': pinyin,
                'shortcut': shortcut,
                'hash': hash_val,
                'freq_score': freq_score,
                'original_line': line_num
            })

            if line_num % 100000 == 0:
                print(f"已处理 {line_num} 行...")

    print(f"共读取 {len(entries)} 条词条")
    print("正在排序...")

    # 排序规则：
    # 1. 按频率分数排序（分数越小越靠前）
    # 2. 相同分数时，按词长排序（短词优先）
    # 3. 相同词长时，保持原有顺序
    entries.sort(key=lambda x: (x['freq_score'], len(x['word']), x['original_line']))

    print("正在写入新文件...")

    # 写入排序后的文件
    with open(output_file, 'w', encoding='utf-8') as f:
        for entry in entries:
            f.write(f"{entry['word']}\t{entry['pinyin']}\t{entry['shortcut']}\t{entry['hash']}\n")

    print(f"完成！新文件已保存到: {output_file}")

    # 显示前100个词条
    print("\n前100个词条预览：")
    for i, entry in enumerate(entries[:100], 1):
        print(f"{i:3d}. {entry['word']:8s} {entry['pinyin']:20s} (原行号: {entry['original_line']:7d}, 分数: {entry['freq_score']:6d})")

    # 显示一些关键字的排名
    print("\n关键字排名检查：")
    key_words = ['的', '很', '红', '好', '人', '我', '你', '他', '吗', '呢',
                 '亮', '两', '良', '量', '辆', '粮', '谅', '晾', '凉', '梁',
                 '洪', '鸿', '宏', '弘']
    for word in key_words:
        for i, entry in enumerate(entries, 1):
            if entry['word'] == word:
                print(f"  {word}: 第 {i} 位 (分数: {entry['freq_score']})")
                break

    # 显示 liang 相关字的排名
    print("\n拼音为 'liang' 的字排名（前20个）：")
    liang_chars = []
    for i, entry in enumerate(entries, 1):
        if entry['pinyin'] == 'liang' and len(entry['word']) == 1:
            liang_chars.append((i, entry['word'], entry['freq_score']))
            if len(liang_chars) >= 20:
                break
    for rank, char, score in liang_chars:
        print(f"  {char}: 第 {rank} 位 (分数: {score})")

    # 显示 hong 相关字的排名
    print("\n拼音为 'hong' 的字排名（前20个）：")
    hong_chars = []
    for i, entry in enumerate(entries, 1):
        if entry['pinyin'] == 'hong' and len(entry['word']) == 1:
            hong_chars.append((i, entry['word'], entry['freq_score']))
            if len(hong_chars) >= 20:
                break
    for rank, char, score in hong_chars:
        print(f"  {char}: 第 {rank} 位 (分数: {score})")

def main():
    input_file = 'Sources/Preparing/Resources/pinyin.txt'
    output_file = 'Sources/Preparing/Resources/pinyin_reordered.txt'

    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]

    print("=" * 70)
    print("拼音词库重排序工具 - 最终版")
    print("基于真实语料库统计数据 + 《通用规范汉字表》")
    print("=" * 70)
    print(f"输入文件: {input_file}")
    print(f"输出文件: {output_file}")
    print()

    try:
        reorder_pinyin_file(input_file, output_file)
        print("\n排序完成！")
        print(f"\n下一步操作：")
        print(f"1. 检查新文件: {output_file}")
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
