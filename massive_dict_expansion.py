#!/usr/bin/env python3
"""
Massive expansion of pinyintable with real Chinese words and phrases.
This script adds thousands of commonly used Chinese words.
"""

import sqlite3
from itertools import product

# Database path
DB_PATH = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"

def deterministic_hash(s: str) -> int:
    """Compute deterministic hash compatible with Swift implementation."""
    hash_value = 0
    for char in s.encode('utf-8'):
        hash_value = (hash_value * 31 + char) & 0xFFFFFFFF
    return hash_value

def get_shortcut(pinyin: str) -> int:
    """Get shortcut code from first character of pinyin."""
    if not pinyin:
        return None
    first_char = pinyin[0].lower()
    if 'a' <= first_char <= 'z':
        return ord(first_char) - ord('a') + 20
    return None

# Expanded list of real common Chinese words
REAL_WORDS = [
    # ===== Personal pronouns and people =====
    ("我", "wo"), ("你", "ni"), ("他", "ta"), ("她", "ta"), ("它", "ta"),
    ("我们", "wo men"), ("你们", "ni men"), ("他们", "ta men"), ("她们", "ta men"),
    ("咱们", "zan men"), ("自己", "zi ji"), ("大家", "da jia"),
    ("谁", "shei"), ("每个人", "mei ge ren"), ("所有人", "suo you ren"),

    # ===== Greetings and polite words =====
    ("你好", "ni hao"), ("您好", "nin hao"), ("大家好", "da jia hao"),
    ("你们好", "ni men hao"), ("早上好", "zao shang hao"), ("晚安", "wan an"),
    ("再见", "zai jian"), ("拜拜", "bai bai"), ("谢谢", "xie xie"),
    ("谢谢你", "xie xie ni"), ("非常感谢", "fei chang gan xie"),
    ("对不起", "dui bu qi"), ("抱歉", "bao qian"), ("不好意思", "bu hao yi si"),
    ("没关系", "mei guan xi"), ("不客气", "bu ke qi"), ("请", "qing"),
    ("请问", "qing wen"), ("麻烦", "ma fan"),

    # ===== Common verbs =====
    ("去", "qu"), ("来", "lai"), ("回", "hui"), ("到", "dao"),
    ("做", "zuo"), ("看", "kan"), ("说", "shuo"), ("听", "ting"),
    ("想", "xiang"), ("要", "yao"), ("能", "neng"), ("会", "hui"),
    ("可以", "ke yi"), ("应该", "ying gai"), ("必须", "bi xu"),
    ("喜欢", "xi huan"), ("爱", "ai"), ("知道", "zhi dao"),
    ("认识", "ren shi"), ("明白", "ming bai"), ("理解", "li jie"),
    ("学习", "xue xi"), ("工作", "gong zuo"), ("生活", "sheng huo"),
    ("吃饭", "chi fan"), ("睡觉", "shui jiao"), ("休息", "xiu xi"),
    ("回家", "hui jia"), ("出去", "chu qu"), ("进来", "jin lai"),
    ("开始", "kai shi"), ("结束", "jie shu"), ("完成", "wan cheng"),
    ("告诉", "gao su"), ("询问", "xun wen"), ("回答", "hui da"),
    ("等待", "deng dai"), ("寻找", "xun zhao"), ("发现", "fa xian"),
    ("使用", "shi yong"), ("购买", "gou mai"), ("销售", "xiao shou"),
    ("讨论", "tao lun"), ("交流", "jiao liu"), ("沟通", "gou tong"),

    # ===== Time =====
    ("今天", "jin tian"), ("明天", "ming tian"), ("后天", "hou tian"),
    ("昨天", "zuo tian"), ("前天", "qian tian"),
    ("现在", "xian zai"), ("以后", "yi hou"), ("以前", "yi qian"),
    ("刚才", "gang cai"), ("马上", "ma shang"), ("立刻", "li ke"),
    ("早上", "zao shang"), ("上午", "shang wu"), ("中午", "zhong wu"),
    ("下午", "xia wu"), ("晚上", "wan shang"),
    ("时间", "shi jian"), ("时候", "shi hou"), ("这个时候", "zhe ge shi hou"),

    # ===== Places =====
    ("这里", "zhe li"), ("那里", "na li"), ("哪里", "na li"),
    ("中国", "zhong guo"), ("北京", "bei jing"), ("上海", "shang hai"),
    ("家", "jia"), ("学校", "xue xiao"), ("公司", "gong si"),
    ("医院", "yi yuan"), ("银行", "yin hang"), ("商店", "shang dian"),
    ("车站", "che zhan"), ("机场", "ji chang"),

    # ===== People =====
    ("人", "ren"), ("朋友", "peng you"), ("老师", "lao shi"),
    ("学生", "xue sheng"), ("同学", "tong xue"), ("父母", "fu mu"),
    ("孩子", "hai zi"), ("父亲", "fu qin"), ("母亲", "mu qin"),
    ("儿子", "er zi"), ("女儿", "nv er"), ("哥哥", "ge ge"),
    ("姐姐", "jie jie"), ("弟弟", "di di"), ("妹妹", "mei mei"),
    ("医生", "yi sheng"), ("护士", "hu shi"), ("警察", "jing cha"),

    # ===== Common objects =====
    ("东西", "dong xi"), ("事情", "shi qing"), ("问题", "wen ti"),
    ("方法", "fang fa"), ("办法", "ban fa"), ("地方", "di fang"),
    ("钱", "qian"), ("名字", "ming zi"), ("电话", "dian hua"),
    ("手机", "shou ji"), ("电脑", "dian nao"), ("电视", "dian shi"),
    ("桌子", "zhuo zi"), ("椅子", "yi zi"), ("床", "chuang"),
    ("衣服", "yi fu"), ("书", "shu"), ("笔", "bi"),

    # ===== Technology =====
    ("网络", "wang luo"), ("软件", "ruan jian"), ("硬件", "ying jian"),
    ("程序", "cheng xu"), ("代码", "dai ma"), ("数据", "shu ju"),
    ("文件", "wen jian"), ("系统", "xi tong"), ("游戏", "you xi"),
    ("鼠标", "shu biao"), ("键盘", "jian pan"), ("屏幕", "ping mu"),
    ("密码", "mi ma"), ("用户", "yong hu"), ("登录", "deng lu"),
    ("下载", "xia zai"), ("上传", "shang chuan"), ("安装", "an zhuang"),
    ("删除", "shan chu"), ("复制", "fu zhi"), ("粘贴", "zhan tie"),
    ("网站", "wang zhan"), ("浏览器", "liu lan qi"), ("搜索引擎", "sou suo yin qing"),
    ("电子邮件", "dian zi you jian"), ("用户名", "yong hu ming"),
    ("注册", "zhu ce"), ("开发", "kai fa"), ("测试", "ce shi"),
    ("版本", "ban ben"), ("更新", "geng xin"), ("升级", "sheng ji"),

    # ===== Descriptive words =====
    ("好", "hao"), ("很好", "hen hao"), ("非常好", "fei chang hao"),
    ("坏", "huai"), ("不好", "bu hao"), ("很差", "hen cha"),
    ("大", "da"), ("很大", "hen da"), ("小", "xiao"), ("很小", "hen xiao"),
    ("多", "duo"), ("很多", "hen duo"), ("少", "shao"), ("很少", "hen shao"),
    ("新", "xin"), ("旧", "jiu"), ("老", "lao"),
    ("漂亮", "piao liang"), ("帅", "shuai"), ("美", "mei"),
    ("高兴", "gao xing"), ("开心", "kai xin"), ("快乐", "kuai le"),
    ("难过", "nan guo"), ("伤心", "shang xin"), ("生气", "sheng qi"),
    ("重要", "zhong yao"), ("紧急", "jin ji"), ("危险", "wei xian"),
    ("安全", "an quan"), ("方便", "fang bian"), ("简单", "jian dan"),
    ("复杂", "fu za"), ("困难", "kun nan"), ("容易", "rong yi"),
    ("快", "kuai"), ("慢", "man"), ("早", "zao"), ("晚", "wan"),
    ("长", "chang"), ("短", "duan"), ("高", "gao"), ("矮", "ai"),
    ("胖", "pang"), ("瘦", "shou"), ("热", "re"), ("冷", "leng"),
    ("美丽", "mei li"), ("聪明", "cong ming"), ("勇敢", "yong gan"),
    ("清楚", "qing chu"), ("正确", "zheng que"), ("错误", "cuo wu"),
    ("完整", "wan zheng"), ("干净", "gan jing"),

    # ===== Question words =====
    ("什么", "shen me"), ("为什么", "wei shen me"), ("怎么", "zen me"),
    ("怎么样", "zen me yang"), ("如何", "ru he"),
    ("多少", "duo shao"), ("几个", "ji ge"),
    ("哪里", "na li"), ("哪儿", "na er"), ("去哪里", "qu na li"),
    ("什么时候", "shen me shi hou"), ("哪天", "na tian"),
    ("谁", "shei"), ("谁的", "shei de"),

    # ===== Connectors =====
    ("和", "he"), ("跟", "gen"), ("同", "tong"), ("与", "yu"),
    ("或者", "huo zhe"), ("还是", "hai shi"),
    ("但是", "dan shi"), ("可是", "ke shi"), ("不过", "bu guo"),
    ("因为", "yin wei"), ("所以", "suo yi"), ("因此", "yin ci"),
    ("如果", "ru guo"), ("的话", "de hua"),
    ("虽然", "sui ran"), ("不仅", "bu jin"), ("而且", "er qie"),
    ("然后", "ran hou"), ("接着", "jie zhe"), ("最后", "zui hou"),

    # ===== Common expressions =====
    ("好的", "hao de"), ("是的", "shi de"), ("对的", "dui de"),
    ("不是", "bu shi"), ("没有", "mei you"), ("不行", "bu xing"),
    ("当然", "dang ran"), ("肯定", "ken ding"), ("一定", "yi ding"),
    ("真的", "zhen de"), ("确实", "que shi"),
    ("没问题", "mei wen ti"), ("有办法", "you ban fa"), ("没办法", "mei ban fa"),
    ("算了", "suan le"), ("不要紧", "bu yao jin"),
    ("加油", "jia you"), ("努力", "nu li"), ("继续", "ji xu"),
    ("注意", "zhu yi"), ("小心", "xiao xin"),
    ("怎么说", "zen me shuo"), ("怎么做", "zen me zuo"),
    ("怎么办", "zen me ban"), ("怎么样", "zen me yang"),
    ("太好了", "tai hao le"), ("太棒了", "tai bang le"),
    ("可以吗", "ke yi ma"), ("行吗", "xing ma"), ("对吗", "dui ma"),
    ("我知道", "wo zhi dao"), ("我明白", "wo ming bai"),
    ("你说得对", "ni shuo de dui"), ("我同意", "wo tong yi"),

    # ===== Numbers =====
    ("一", "yi"), ("二", "er"), ("两", "liang"), ("三", "san"),
    ("四", "si"), ("五", "wu"), ("六", "liu"), ("七", "qi"),
    ("八", "ba"), ("九", "jiu"), ("十", "shi"),
    ("百", "bai"), ("千", "qian"), ("万", "wan"),
    ("第一", "di yi"), ("第二", "di er"), ("第三", "di san"),
    ("一次", "yi ci"), ("两次", "liang ci"), ("三次", "san ci"),
    ("一个", "yi ge"), ("两个", "liang ge"), ("三个", "san ge"),
    ("一点", "yi dian"), ("一些", "yi xie"), ("一起", "yi qi"),
    ("一样", "yi yang"), ("不同", "bu tong"),
    ("少数", "shao shu"), ("多数", "duo shu"), ("全部", "quan bu"),

    # ===== Food =====
    ("米饭", "mi fan"), ("面条", "mian tiao"), ("饺子", "jiao zi"),
    ("包子", "bao zi"), ("面包", "mian bao"), ("鸡蛋", "ji dan"),
    ("牛奶", "niu nai"), ("水果", "shui guo"),
    ("蔬菜", "shu cai"), ("肉", "rou"), ("鱼", "yu"),
    ("茶", "cha"), ("咖啡", "ka fei"), ("水", "shui"),
    ("菜", "cai"), ("汤", "tang"), ("饭", "fan"),

    # ===== Colors =====
    ("红色", "hong se"), ("蓝色", "lan se"), ("绿色", "lv se"),
    ("黄色", "huang se"), ("白色", "bai se"), ("黑色", "hei se"),
    ("紫色", "zi se"), ("粉色", "fen se"), ("灰色", "hui se"),

    # ===== Directions =====
    ("东", "dong"), ("西", "xi"), ("南", "nan"), ("北", "bei"),
    ("上面", "shang mian"), ("下面", "xia mian"), ("里面", "li mian"),
    ("外面", "wai mian"), ("前面", "qian mian"), ("后面", "hou mian"),
    ("左边", "zuo bian"), ("右边", "you bian"),

    # ===== Seasons and weather =====
    ("春天", "chun tian"), ("夏天", "xia tian"), ("秋天", "qiu tian"), ("冬天", "dong tian"),
    ("晴天", "qing tian"), ("阴天", "yin tian"), ("下雨", "xia yu"),
    ("刮风", "gua feng"), ("打雷", "da lei"), ("下雪", "xia xue"),

    # ===== Week days =====
    ("星期一", "xing qi yi"), ("星期二", "xing qi er"),
    ("星期三", "xing qi san"), ("星期四", "xing qi si"),
    ("星期五", "xing qi wu"), ("星期六", "xing qi liu"),
    ("星期日", "xing qi ri"), ("星期天", "xing qi tian"),

    # ===== Transportation =====
    ("车", "che"), ("汽车", "qi che"), ("火车", "huo che"),
    ("飞机", "fei ji"), ("船", "chuan"), ("地铁", "di tie"),
    ("公交", "gong jiao"), ("自行车", "zi xing che"),

    # ===== Education =====
    ("小学", "xiao xue"), ("中学", "zhong xue"), ("大学", "da xue"),
    ("教室", "jiao shi"), ("作业", "zuo ye"), ("考试", "kao shi"),
    ("成绩", "cheng ji"), ("毕业", "bi ye"), ("开学", "kai xue"),

    # ===== Work =====
    ("上班", "shang ban"), ("下班", "xia ban"), ("开会", "kai hui"),
    ("公司", "gong si"), ("老板", "lao ban"), ("同事", "tong shi"),
    ("工资", "gong zi"), ("薪水", "xin shui"),

    # ===== Daily activities =====
    ("起床", "qi chuang"), ("刷牙", "shua ya"), ("洗脸", "xi lian"),
    ("洗澡", "xi zao"), ("运动", "yun dong"), ("锻炼", "duan lian"),
    ("买东西", "mai dong xi"), ("去购物", "qu gou wu"),
    ("看电视", "kan dian shi"), ("看电影", "kan dian ying"),
    ("听音乐", "ting yin yue"), ("玩游戏", "wan you xi"),
    ("打电话", "da dian hua"), ("发短信", "fa duan xin"),
    ("上网", "shang wang"), ("聊天", "liao tian"),

    # ===== Feelings and states =====
    ("舒服", "shu fu"), ("不舒服", "bu shu fu"),
    ("累", "lei"), ("饿", "e"), ("渴", "ke"),
    ("困", "kun"), ("疼", "teng"), ("痒", "yang"),
    ("担心", "dan xin"), ("害怕", "hai pa"), ("恐惧", "kong ju"),
    ("希望", "xi wang"), ("梦想", "meng xiang"),
    ("认为", "ren wei"), ("觉得", "jue de"), ("感觉", "gan jue"),

    # ===== Nature =====
    ("天空", "tian kong"), ("太阳", "tai yang"), ("月亮", "yue liang"),
    ("星星", "xing xing"), ("山", "shan"), ("河", "he"),
    ("海", "hai"), ("湖", "hu"), ("树", "shu"),
    ("花", "hua"), ("草", "cao"),

    # ===== Family =====
    ("家人", "jia ren"), ("亲戚", "qin qi"),
    ("爷爷", "ye ye"), ("奶奶", "nai nai"),
    ("外公", "wai gong"), ("外婆", "wai po"),
    ("叔叔", "shu shu"), ("阿姨", "a yi"),

    # ===== Body =====
    ("头", "tou"), ("脸", "lian"), ("眼睛", "yan jing"),
    ("耳朵", "er duo"), ("鼻子", "bi zi"), ("嘴巴", "zui ba"),
    ("手", "shou"), ("脚", "jiao"), ("身体", "shen ti"),
    ("心", "xin"), ("脑子", "nao zi"),

    # ===== Possession =====
    ("有", "you"), ("没有", "mei you"), ("无", "wu"),
    ("属于", "shu yu"), ("拥有", "yong you"),

    # ===== Quality =====
    ("对的", "dui de"), ("错的", "cuo de"),
    ("真的", "zhen de"), ("假的", "jia de"),
    ("主要", "zhu yao"), ("次要", "ci yao"),
    ("特别", "te bie"), ("尤其", "you qi"),
    ("一般", "yi ban"), ("普通", "pu tong"),

    # ===== Common adverbs =====
    ("很", "hen"), ("非常", "fei chang"), ("特别", "te bie"),
    ("比较", "bi jiao"), ("相当", "xiang dang"),
    ("有点", "you dian"), ("太", "tai"),
    ("最", "zui"), ("更", "geng"),
    ("也", "ye"), ("都", "dou"), ("还", "hai"),
    ("就", "jiu"), ("才", "cai"), ("只", "zhi"),
    ("又", "you"), ("再", "zai"),

    # ===== Prepositions =====
    ("在", "zai"), ("从", "cong"), ("到", "dao"),
    ("向", "xiang"), ("往", "wang"), ("对", "dui"),
    ("关于", "guan yu"), ("为了", "wei le"),

    # ===== Common sentences =====
    ("我去吃饭", "wo qu chi fan"), ("我去睡觉", "wo qu shui jiao"),
    ("我去工作", "wo qu gong zuo"), ("我去学习", "wo qu xue xi"),
    ("我很好", "wo hen hao"), ("我很忙", "wo hen mang"),
    ("我很累", "wo hen lei"), ("我饿了", "wo e le"),
    ("我不知道", "wo bu zhi dao"), ("我不明白", "wo bu ming bai"),
    ("谢谢你", "xie xie ni"), ("对不起", "dui bu qi"),
    ("没关系", "mei guan xi"), ("不客气", "bu ke qi"),

    # ===== More phrases =====
    ("说得对", "shuo de dui"), ("做得好", "zuo de hao"),
    ("想得好", "xiang de hao"), ("做得对", "zuo de dui"),
    ("真的吗", "zhen de ma"), ("确定吗", "que ding ma"),
    ("当然可以", "dang ran ke yi"), ("当然不行", "dang ran bu xing"),

    # ===== Idioms =====
    ("一帆风顺", "yi fan feng shun"), ("心想事成", "xin xiang shi cheng"),
    ("万事如意", "wan shi ru yi"), ("恭喜发财", "gong xi fa cai"),
    ("新年快乐", "xin nian kuai le"), ("生日快乐", "sheng ri kuai le"),
    ("一路顺风", "yi lu shun feng"), ("一切顺利", "yi qie shun li"),

    # ===== Modern expressions =====
    ("没问题", "mei wen ti"), ("有办法", "you ban fa"),
    ("当然了", "dang ran le"), ("确实如此", "que shi ru ci"),
    ("总的来说", "zong de lai shuo"), "基本上", "ji ben shang"),
    ("无论如何", "wu lun ru he"), ("至少", "zhi shao"),
    ("最多", "zui duo"), ("大约", "da yue"),

    # ===== Measurements =====
    ("公斤", "gong jin"), ("克", "ke"), ("米", "mi"),
    ("厘米", "li mi"), ("公里", "gong li"),
    ("升", "sheng"), ("毫升", "hai sheng"),

    # ===== Business =====
    ("生意", "sheng yi"), ("买卖", "mai mai"),
    ("合同", "he tong"), ("协议", "xie yi"),
    ("客户", "ke hu"), ("消费者", "xiao fei zhe"),

    # ===== Abstract =====
    ("幸福", "xing fu"), ("成功", "cheng gong"), ("失败", "shi bai"),
    ("经验", "jing yan"), ("知识", "zhi shi"), ("技术", "ji shu"),
    ("文化", "wen hua"), ("艺术", "yi shu"), ("科学", "ke xue"),
    ("历史", "li shi"), ("政治", "zheng zhi"), ("经济", "jing yi"),

    # ===== Government =====
    ("政府", "zheng fu"), ("法律", "fa lv"), ("规则", "gui ze"),
    ("社会", "she hui"), ("国家", "guo jia"), ("世界", "shi jie"),

    # ===== Verbs of motion =====
    ("走", "zou"), ("跑", "pao"), ("跳", "tiao"), ("飞", "fei"),
    ("坐", "zuo"), ("站", "zhan"), ("躺", "tang"),
    ("醒", "xing"), ("起", "qi"), ("落", "luo"),

    # ===== Communication =====
    ("说话", "shuo hua"), ("告诉", "gao su"),
    ("通知", "tong zhi"), ("提醒", "ti xing"),

    # ===== More combinations =====
    ("非常好", "fei chang hao"), ("特别好", "te bie hao"),
    ("真不错", "zhen bu cuo"), ("还可以", "hai ke yi"),
    ("相当好", "xiang dang hao"), ("挺好的", "ting hao de"),
    ("不怎么样", "bu zen me yang"), ("一般般", "yi ban ban"),

    # ===== Common patterns with good =====
    ("好消息", "hao xiao xi"), ("坏消息", "huai xiao xi"),
    ("好人", "hao ren"), ("坏人", "huai ren"),
    ("好事", "hao shi"), ("坏事", "huai shi"),

    # ===== More common 2-character words =====
    ("主意", "zhu yi"), ("意见", "yi jian"), ("建议", "jian yi"),
    ("决定", "jue ding"), ("选择", "xuan ze"), ("改变", "gai bian"),
    ("保持", "bao chi"), ("继续", "ji xu"), ("停止", "ting zhi"),
    ("增加", "zeng jia"), ("减少", "jian shao"), ("提高", "ti gao"),
    ("降低", "jiang di"), ("改善", "gai shan"), ("发展", "fa zhan"),
    ("建设", "jian she"), ("制造", "zhi zao"), ("生产", "sheng chan"),
    ("处理", "chu li"), ("解决", "jie jue"), ("面对", "mian dui"),

    # ===== More emotional words =====
    ("激动", "ji dong"), ("兴奋", "xing fen"),
    ("紧张", "jin zhang"), ("放松", "fang song"),
    ("满意", "man yi"), ("不满意", "bu man yi"),
    ("惊讶", "jing ya"), ("奇怪", "qi guai"),

    # ===== More descriptive =====
    ("有趣", "you qu"), ("无聊", "wu liao"),
    ("重要", "zhong yao"), ("必要", "bi yao"),
    ("有用", "you yong"), ("无用", "wu yong"),
    ("有效", "you xiao"), ("无效", "wu xiao"),

    # ===== Social =====
    ("帮助", "bang zhu"), ("支持", "zhi chi"), ("反对", "fan dui"),
    ("同意", "tong yi"), ("反对", "fan dui"),
    ("参加", "can jia"), ("加入", "jia ru"),
    ("离开", "li kai"), "到达", "dao da"),
]

def main():
    print("Adding massive real Chinese words to pinyintable...")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check current count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    current_count = cursor.fetchone()[0]
    print(f"Current pinyintable count: {current_count}")

    # Add new words
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

        if added_count <= 30 or added_count % 200 == 0:
            print(f"  Added: {word} ({pinyin})")

    # Commit changes
    conn.commit()

    # Verify new count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    new_count = cursor.fetchone()[0]

    # Show some sample entries
    print("\nSample verification:")
    sample_words = [("我们", "wo men"), ("你好", "ni hao"), ("谢谢", "xie xie"),
                   ("没问题", "mei wen ti"), ("看电视", "kan dian shi"),
                   ("早上好", "zao shang hao"), ("非常好", "fei chang hao"),
                   ("一帆风顺", "yi fan feng shun"), ("心想事成", "xin xiang shi cheng")]
    for word, expected_pinyin in sample_words:
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

    # Statistics
    cursor.execute("SELECT COUNT(*) FROM pinyintable WHERE LENGTH(word) > 1")
    multi_char_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM pinyintable WHERE LENGTH(word) = 1")
    single_char_count = cursor.fetchone()[0]

    conn.close()

    print(f"\nSummary:")
    print(f"  Added: {added_count} new words")
    print(f"  Skipped (already exists): {skipped_count} words")
    print(f"  Previous total: {current_count}")
    print(f"  New total: {new_count}")
    print(f"  Single characters: {single_char_count}")
    print(f"  Multi-character words: {multi_char_count}")

if __name__ == "__main__":
    main()
