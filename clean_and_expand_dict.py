#!/usr/bin/env python3
"""
Clean invalid entries and add real common Chinese phrases.
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

def get_shortcut(pinyin: str) -> int:
    """Get shortcut code from first character of pinyin."""
    if not pinyin:
        return None
    first_char = pinyin[0].lower()
    if 'a' <= first_char <= 'z':
        return ord(first_char) - ord('a') + 20
    return None

# Real common Chinese words and phrases - manually curated
REAL_COMMON_PHRASES = [
    # Pronouns and personal words
    ("我们", "wo men"), ("你们", "ni men"), ("他们", "ta men"), ("她们", "ta men"),
    ("咱们", "zan men"), ("自己", "zi ji"), ("大家", "da jia"),
    ("我", "wo"), ("你", "ni"), ("他", "ta"), ("她", "ta"), ("它", "ta"),
    ("谁", "shei"), ("什么人", "shen me ren"), ("这个人", "zhe ge ren"),

    # Greetings
    ("你好", "ni hao"), ("您好", "nin hao"), ("大家好", "da jia hao"),
    ("你们好", "ni men hao"), ("老师好", "lao shi hao"), ("早上好", "zao shang hao"),
    ("晚安", "wan an"), ("再见", "zai jian"), ("拜拜", "bai bai"),

    # Politeness
    ("谢谢", "xie xie"), ("谢谢你", "xie xie ni"), ("非常感谢", "fei chang gan xie"),
    ("对不起", "dui bu qi"), ("抱歉", "bao qian"), ("不好意思", "bu hao yi si"),
    ("没关系", "mei guan xi"), ("不要紧", "bu yao jin"), ("不客气", "bu ke qi"),
    ("请", "qing"), ("请问", "qing wen"), ("麻烦你", "ma fan ni"),

    # Common verbs
    ("去", "qu"), ("来", "lai"), ("回", "hui"), ("到", "dao"),
    ("做", "zuo"), ("看", "kan"), ("说", "shuo"), ("想", "xiang"), ("要", "yao"),
    ("能", "neng"), ("会", "hui"), ("可以", "ke yi"), ("应该", "ying gai"),
    ("喜欢", "xi huan"), ("爱", "ai"), ("知道", "zhi dao"), ("认识", "ren shi"),
    ("明白", "ming bai"), ("理解", "li jie"), ("相信", "xiang xin"),
    ("学习", "xue xi"), ("工作", "gong zuo"), ("生活", "sheng huo"),
    ("吃饭", "chi fan"), ("睡觉", "shui jiao"), ("休息", "xiu xi"),
    ("回家", "hui jia"), ("出去", "chu qu"), ("进来", "jin lai"),
    ("开始", "kai shi"), ("结束", "jie shu"), ("完成", "wan cheng"),

    # Time
    ("今天", "jin tian"), ("明天", "ming tian"), ("后天", "hou tian"),
    ("昨天", "zuo tian"), ("前天", "qian tian"),
    ("现在", "xian zai"), ("以后", "yi hou"), ("以前", "yi qian"),
    ("刚才", "gang cai"), ("马上", "ma shang"), ("立刻", "li ke"),
    ("早上", "zao shang"), ("上午", "shang wu"), ("中午", "zhong wu"),
    ("下午", "xia wu"), ("晚上", "wan shang"), ("半夜", "ban ye"),
    ("时间", "shi jian"), ("时候", "shi hou"), ("这个时候", "zhe ge shi hou"),

    # Places
    ("中国", "zhong guo"), ("北京", "bei jing"), ("上海", "shang hai"),
    ("家", "jia"), ("这里", "zhe li"), ("那里", "na li"), ("哪里", "na li"),
    ("学校", "xue xiao"), ("公司", "gong si"), ("医院", "yi yuan"),
    ("银行", "yin hang"), ("商店", "shang dian"), ("超市", "chao shi"),
    ("车站", "che zhan"), ("机场", "ji chang"), ("图书馆", "tu shu guan"),

    # People
    ("人", "ren"), ("男人", "nan ren"), ("女人", "nv ren"),
    ("孩子", "hai zi"), ("小孩", "xiao hai"), ("大人", "da ren"),
    ("老师", "lao shi"), ("学生", "xue sheng"), ("同学", "tong xue"),
    ("朋友", "peng you"), ("父母", "fu mu"), ("父亲", "fu qin"), ("母亲", "mu qin"),
    ("儿子", "er zi"), ("女儿", "nv er"), ("哥哥", "ge ge"), ("姐姐", "jie jie"),
    ("弟弟", "di di"), ("妹妹", "mei mei"),
    ("医生", "yi sheng"), ("护士", "hu shi"), ("警察", "jing cha"),

    # Common objects
    ("东西", "dong xi"), ("事情", "shi qing"), ("问题", "wen ti"),
    ("方法", "fang fa"), ("办法", "ban fa"), ("地方", "di fang"),
    ("钱", "qian"), ("名字", "ming zi"), ("电话", "dian hua"),
    ("手机", "shou ji"), ("电脑", "dian nao"), ("电视", "dian shi"),
    ("桌子", "zhuo zi"), ("椅子", "yi zi"), ("床", "chuang"),
    ("衣服", "yi fu"), ("鞋子", "xie zi"),
    ("书", "shu"), ("笔", "bi"), ("纸", "zhi"),

    # Technology
    ("网络", "wang luo"), ("互联网", "hu lian wang"), ("网站", "wang zhan"),
    ("软件", "ruan jian"), ("硬件", "ying jian"), ("程序", "cheng xu"),
    ("代码", "dai ma"), ("数据", "shu ju"), ("文件", "wen jian"),
    ("系统", "xi tong"), ("应用", "ying yong"), ("游戏", "you xi"),
    ("鼠标", "shu biao"), ("键盘", "jian pan"), ("屏幕", "ping mu"),
    ("密码", "mi ma"), ("用户", "yong hu"), ("登录", "deng lu"),
    ("下载", "xia zai"), ("上传", "shang chuan"), ("安装", "an zhuang"),
    ("删除", "shan chu"), ("复制", "fu zhi"), ("粘贴", "zhan tie"),

    # Descriptive words
    ("好", "hao"), ("很好", "hen hao"), ("非常好", "fei chang hao"),
    ("坏", "huai"), ("不好", "bu hao"), ("很差", "hen cha"),
    ("大", "da"), ("很大", "hen da"), ("很大", "hen da"),
    ("小", "xiao"), ("很小", "hen xiao"), ("小", "xiao"),
    ("多", "duo"), ("很多", "hen duo"), ("少", "shao"), ("很少", "hen shao"),
    ("漂亮", "piao liang"), ("帅", "shuai"), ("美", "mei"),
    ("高兴", "gao xing"), ("开心", "kai xin"), ("快乐", "kuai le"),
    ("难过", "nan guo"), ("伤心", "shang xin"), ("生气", "sheng qi"),
    ("重要", "zhong yao"), ("紧急", "jin ji"), ("危险", "wei xian"),
    ("安全", "an quan"), ("方便", "fang bian"), ("简单", "jian dan"),
    ("复杂", "fu za"), ("困难", "kun nan"), ("容易", "rong yi"),
    ("新", "xin"), ("旧", "jiu"), ("老", "lao"),
    ("快", "kuai"), ("慢", "man"), ("早", "zao"), ("晚", "wan"),
    ("长", "chang"), ("短", "duan"), ("高", "gao"), ("矮", "ai"),
    ("胖", "pang"), ("瘦", "shou"), ("热", "re"), ("冷", "leng"),

    # Question words
    ("什么", "shen me"), ("为什么", "wei shen me"), ("怎么", "zen me"),
    ("怎么样", "zen me yang"), ("如何", "ru he"),
    ("多少", "duo shao"), ("几个", "ji ge"), ("哪几个", "na ji ge"),
    ("哪里", "na li"), ("哪儿", "na er"), ("去哪里", "qu na li"),
    ("什么时候", "shen me shi hou"), ("哪天", "na tian"),
    ("谁", "shei"), ("谁的", "shei de"), ("谁家", "shei jia"),

    # Connectors
    ("和", "he"), ("跟", "gen"), ("同", "tong"), ("与", "yu"),
    ("或者", "huo zhe"), ("还是", "hai shi"),
    ("但是", "dan shi"), ("可是", "ke shi"), ("不过", "bu guo"),
    ("因为", "yin wei"), ("所以", "suo yi"), ("因此", "yin ci"),
    ("如果", "ru guo"), ("要是", "yao shi"), ("的话", "de hua"),
    ("虽然", "sui ran"), ("但是", "dan shi"),
    ("不仅", "bu jin"), ("而且", "er qie"),
    ("然后", "ran hou"), ("接着", "jie zhe"), ("最后", "zui hou"),

    # Common expressions
    ("好的", "hao de"), ("是的", "shi de"), ("对的", "dui de"),
    ("不是", "bu shi"), ("没有", "mei you"), ("不行", "bu xing"),
    ("可以", "ke yi"), ("当然", "dang ran"), ("肯定", "ken ding"),
    ("应该", "ying gai"), ("必须", "bi xu"), ("一定", "yi ding"),
    ("真的", "zhen de"), ("确实", "que shi"), ("当然", "dang ran"),
    ("没问题", "mei wen ti"), ("有办法", "you ban fa"), ("没办法", "mei ban fa"),
    ("没关系", "mei guan xi"), ("算了", "suan le"), ("不要紧", "bu yao jin"),

    # Common phrases
    ("加油", "jia you"), ("努力", "nu li"), ("继续", "ji xu"),
    ("注意", "zhu yi"), ("小心", "xiao xin"), ("当心", "dang xin"),
    ("没关系", "mei guan xi"), ("对不起", "dui bu qi"), ("谢谢", "xie xie"),

    # Numbers and quantities
    ("一", "yi"), ("二", "er"), ("三", "san"), ("四", "si"),
    ("五", "wu"), ("六", "liu"), ("七", "qi"), ("八", "ba"),
    ("九", "jiu"), ("十", "shi"), ("百", "bai"), ("千", "qian"), ("万", "wan"),
    ("第一", "di yi"), ("第二", "di er"), ("第三", "di san"),
    ("一次", "yi ci"), ("两次", "liang ci"), ("三次", "san ci"),
    ("一个", "yi ge"), ("两个", "liang ge"), ("三个", "san ge"),
    ("一点", "yi dian"), ("一些", "yi xie"), ("一起", "yi qi"),
    ("一样", "yi yang"), ("不同", "bu tong"), ("一样", "yi yang"),

    # Food
    ("米饭", "mi fan"), ("面条", "mian tiao"), ("饺子", "jiao zi"),
    ("包子", "bao zi"), ("面包", "mian bao"),
    ("牛奶", "niu nai"), ("鸡蛋", "ji dan"), ("水果", "shui guo"),
    ("菜", "cai"), ("肉", "rou"), ("鱼", "yu"), ("鸡", "ji"),
    ("茶", "cha"), ("咖啡", "ka fei"), ("水", "shui"),

    # Abstract concepts
    ("幸福", "xing fu"), ("成功", "cheng gong"), ("失败", "shi bai"),
    ("经验", "jing yan"), ("知识", "zhi shi"), ("技术", "ji shu"),
    ("文化", "wen hua"), ("艺术", "yi shu"), ("科学", "ke xue"),
    ("历史", "li shi"), ("政治", "zheng zhi"), ("经济", "jing ji"),

    # Daily activities
    ("看电视", "kan dian shi"), ("看电影", "kan dian ying"),
    ("听音乐", "ting yin yue"), ("玩游戏", "wan you xi"),
    ("打电话", "da dian hua"), ("上网", "shang wang"),
    ("发短信", "fa duan xin"), ("聊天", "liao tian"),
    ("买东西", "mai dong xi"), ("去购物", "qu gou wu"),

    # Directions and positions
    ("上面", "shang mian"), ("下面", "xia mian"), ("里面", "li mian"),
    ("外面", "wai mian"), ("前面", "qian mian"), ("后面", "hou mian"),
    ("左边", "zuo bian"), ("右边", "you bian"),
    ("东", "dong"), ("西", "xi"), ("南", "nan"), ("北", "bei"),
    ("中间", "zhong jian"), ("旁边", "pang bian"),

    # Colors
    ("红色", "hong se"), ("蓝色", "lan se"), ("绿色", "lv se"),
    ("黄色", "huang se"), ("白色", "bai se"), ("黑色", "hei se"),
    ("紫色", "zi se"), ("粉色", "fen se"), ("灰色", "hui se"),

    # Seasons and weather
    ("春天", "chun tian"), ("夏天", "xia tian"), ("秋天", "qiu tian"), ("冬天", "dong tian"),
    ("晴天", "qing tian"), ("阴天", "yin tian"), ("下雨", "xia yu"),
    ("刮风", "gua feng"), ("打雷", "da lei"),

    # Week days
    ("星期一", "xing qi yi"), ("星期二", "xing qi er"), ("星期三", "xing qi san"),
    ("星期四", "xing qi si"), ("星期五", "xing qi wu"), ("星期六", "xing qi liu"),
    ("星期日", "xing qi ri"), ("星期天", "xing qi tian"),

    # Common sentences
    ("我去吃饭", "wo qu chi fan"), ("我去睡觉", "wo qu shui jiao"),
    ("我很好", "wo hen hao"), ("我很忙", "wo hen mang"), ("我很累", "wo hen lei"),
    ("你知道吗", "ni zhi dao ma"), ("我明白了", "wo ming bai le"),
    ("说得对", "shuo de dui"), ("做得好", "zuo de hao"),
    ("太好了", "tai hao le"), ("太棒了", "tai bang le"),
    ("怎么样", "zen me yang"), ("还可以", "hai ke yi"),
    ("当然可以", "dang ran ke yi"), ("没问题", "mei wen ti"),

    # Government and society
    ("政府", "zheng fu"), ("法律", "fa lv"), ("规则", "gui ze"),
    ("社会", "she hui"), ("国家", "guo jia"), ("世界", "shi jie"),

    # Body parts
    ("头", "tou"), ("脸", "lian"), ("眼睛", "yan jing"), ("耳朵", "er duo"),
    ("鼻子", "bi zi"), ("嘴巴", "zui ba"), ("手", "shou"), ("脚", "jiao"),
    ("身体", "shen ti"), ("心", "xin"),

    # Feelings
    ("舒服", "shu fu"), ("不舒服", "bu shu fu"),
    ("累", "lei"), ("饿", "e"), ("渴", "ke"),
    ("困", "kun"), ("疼", "teng"), ("痒", "yang"),

    # Idioms and four-character phrases
    ("一帆风顺", "yi fan feng shun"), ("心想事成", "xin xiang shi cheng"),
    ("万事如意", "wan shi ru yi"), ("恭喜发财", "gong xi fa cai"),
    ("新年快乐", "xin nian kuai le"), ("生日快乐", "sheng ri kuai le"),

    # Modern terms
    ("开发", "kai fa"), ("测试", "ce shi"), ("发布", "fa bu"),
    ("版本", "ban ben"), ("更新", "geng xin"), ("升级", "sheng ji"),
    ("浏览器", "liu lan qi"), ("搜索引擎", "sou suo yin qing"),
    ("电子邮件", "dian zi you jian"), ("用户名", "yong hu ming"),
    ("注册", "zhu ce"), ("登录", "deng lu"), ("退出", "tui chu"),

    # More common phrases
    ("说真的", "shuo zhen de"), ("说实话", "shuo shi hua"),
    ("想一想", "xiang yi xiang"), ("看一看", "kan yi kan"),
    ("试一试", "shi yi shi"), ("做一做", "zuo yi zuo"),

    ("确实如此", "que shi ru ci"), ("毫无疑问", "hao wu yi wen"),
    ("总的来说", "zong de lai shuo"), ("基本上", "ji ben shang"),

    ("无论如何", "wu lun ru he"), ("反正", "fan zheng"),
    ("至少", "zhi shao"), ("最多", "zui duo"), ("大约", "da yue"),

    # Family terms
    ("家人", "jia ren"), ("亲戚", "qin qi"),
    ("爷爷", "ye ye"), ("奶奶", "nai nai"), ("外公", "wai gong"), ("外婆", "wai po"),
    ("叔叔", "shu shu"), ("阿姨", "a yi"), ("堂兄", "tang xiong"),

    # Nature
    ("天空", "tian kong"), ("太阳", "tai yang"), ("月亮", "yue liang"),
    ("星星", "xing xing"), ("云", "yun"),
    ("山", "shan"), ("河", "he"), ("海", "hai"), ("湖", "hu"),
    ("树", "shu"), ("花", "hua"), ("草", "cao"),

    # Transportation
    ("车", "che"), ("汽车", "qi che"), ("火车", "huo che"), ("飞机", "fei ji"),
    ("船", "chuan"), ("地铁", "di tie"), ("公交", "gong jiao"),
    ("自行车", "zi xing che"), ("摩托车", "mo tuo che"),

    # Education
    ("小学", "xiao xue"), ("中学", "zhong xue"), ("大学", "da xue"),
    ("教室", "jiao shi"), ("宿舍", "su she"), ("食堂", "shi tang"),
    ("作业", "zuo ye"), ("考试", "kao shi"), ("成绩", "cheng ji"),
    ("毕业", "bi ye"), ("开学", "kai xue"), ("放假", "fang jia"),

    # More common verbs
    ("告诉", "gao su"), ("询问", "xun wen"), ("回答", "hui da"),
    ("等待", "deng dai"), ("寻找", "xun zhao"), ("发现", "fa xian"),
    ("使用", "shi yong"), ("购买", "gou mai"), ("销售", "xiao shou"),
    ("生产", "sheng chan"), ("制造", "zhi zao"), ("建设", "jian she"),

    # More descriptive words
    ("美丽", "mei li"), ("丑陋", "chou lou"),
    ("聪明", "cong ming"), ("愚蠢", "yu chun"),
    ("勇敢", "yong gan"), ("胆小", "dan xiao"),
    ("大方", "da fang"), ("小气", "xiao qi"),
    ("热情", "re qing"), ("冷淡", "leng dan"),

    # Common adverbs
    ("很", "hen"), ("非常", "fei chang"), ("特别", "te bie"),
    ("比较", "bi jiao"), ("相当", "xiang dang"), ("有点", "you dian"),
    ("太", "tai"), ("真", "zhen"), ("最", "zui"), ("更", "geng"),
    ("也", "ye"), ("都", "dou"), ("还", "hai"), ("就", "jiu"),
    ("才", "cai"), ("只", "zhi"), ("又", "you"), ("再", "zai"),

    # Common prepositions
    ("在", "zai"), ("从", "cong"), ("到", "dao"),
    ("向", "xiang"), ("往", "wang"), ("对", "dui"),
    ("关于", "guan yu"), ("为了", "wei le"),

    # More common phrases
    ("怎么说", "zen me shuo"), ("怎么做", "zen me zuo"),
    ("怎么办", "zen me ban"), ("怎么看", "zen me kan"),
    ("写什么", "xie shen me"), ("看什么", "kan shen me"),

    ("一切顺利", "yi qie shun li"), ("一路顺风", "yi lu shun feng"),
    ("多多保重", "duo duo bao zhong"),

    # Measurements
    ("公斤", "gong jin"), ("克", "ke"), ("米", "mi"), ("厘米", "li mi"),
    ("公里", "gong li"), ("升", "sheng"), ("毫升", "hai sheng"),

    # Verbs of motion and action
    ("走", "zou"), ("跑", "pao"), ("跳", "tiao"), ("飞", "fei"),
    ("坐", "zuo"), ("站", "zhan"), ("躺", "tang"), ("睡", "shui"),
    ("醒", "xing"), ("起", "qi"), ("落", "luo"),

    # Communication
    ("说话", "shuo hua"), ("聊天", "liao tian"), ("讨论", "tao lun"),
    ("交流", "jiao liu"), ("沟通", "gou tong"),
    ("告诉", "gao su"), ("通知", "tong zhi"), ("提醒", "ti xing"),

    # Thinking and feeling
    ("认为", "ren wei"), ("觉得", "jue de"), ("感觉", "gan jue"),
    ("希望", "xi wang"), ("梦想", "meng xiang"),
    ("担心", "dan xin"), ("害怕", "hai pa"), ("恐惧", "kong ju"),

    # Possession and existence
    ("有", "you"), ("没有", "mei you"), ("无", "wu"),
    ("属于", "shu yu"), ("拥有", "yong you"),

    # Quality and state
    ("清楚", "qing chu"), ("明确", "ming que"),
    ("正确", "zheng que"), ("错误", "cuo wu"),
    ("完整", "wan zheng"), ("破碎", "po sui"),
    ("干净", "gan jing"), ("肮脏", "ang zang"),
]

def main():
    print("Cleaning invalid entries and adding real common phrases...")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # First, remove obviously invalid entries (unnatural combinations)
    # These are entries where certain characters should never combine with others
    invalid_patterns = [
        ("我", ["地", "得", "着", "过", "品", "具", "法", "式", "意", "心", "面", "起"]),
        ("你", ["地", "得", "着", "过", "品", "具", "法", "式"]),
        ("他", ["地", "得", "着", "过", "品", "具", "法", "式"]),
        ("好", ["子", "儿", "头", "品", "具", "法", "式"]),
        ("大", ["心", "意", "面", "起", "品", "具", "法", "式"]),
        ("小", ["心", "意", "面", "起", "品", "具", "法", "式"]),
        ("说", ["意", "法", "式", "品", "具"]),
        ("学", ["儿", "心", "意", "面", "起", "品", "具", "法", "式"]),
        ("少", ["样", "子", "儿", "头", "品", "具", "法", "式"]),
        ("没", ["面", "起", "品", "具", "法", "式", "意"]),
        ("真", ["候", "候", "样", "子", "儿", "头", "品", "具", "法", "式"]),
        ("或", ["样", "子", "儿", "头", "品", "具", "法", "式"]),
        ("始", ["方", "法", "式", "品", "具"]),
        ("前", ["心", "意", "面", "起", "品", "具", "法", "式"]),
        ("云", ["子", "儿", "头", "品", "具", "法", "式"]),
        ("三", ["的", "得", "地", "着", "过", "子", "儿", "头", "品", "具", "法", "式"]),
        ("千", ["外", "内", "中", "的", "得", "地", "着", "过", "子", "儿", "头", "品", "具", "法", "式"]),
        ("车", ["时", "候", "心", "意", "面", "起", "品", "具", "法", "式"]),
        ("据", ["意", "法", "式", "品", "具"]),
        ("快", ["儿", "心", "意", "面", "起", "品", "具", "法", "式"]),
        ("文", ["地", "得", "着", "过", "品", "具", "法", "式"]),
        ("报", ["内", "外", "中", "的", "得", "地", "着", "过", "子", "儿", "头", "品", "具", "法", "式"]),
        ("进", ["步", "子", "儿", "头", "品", "具", "法", "式"]),
    ]

    deleted_count = 0
    for first_char, invalid_second_chars in invalid_patterns:
        for second_char in invalid_second_chars:
            word = first_char + second_char
            cursor.execute("DELETE FROM pinyintable WHERE word = ?", (word,))
            if cursor.rowcount > 0:
                deleted_count += cursor.rowcount

    conn.commit()
    print(f"Deleted {deleted_count} invalid entries")

    # Add real common phrases
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    current_count = cursor.fetchone()[0]
    print(f"Current count after cleanup: {current_count}")

    added_count = 0
    skipped_count = 0

    for word, pinyin in REAL_COMMON_PHRASES:
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

    # Commit changes
    conn.commit()

    # Verify new count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    new_count = cursor.fetchone()[0]

    # Show some sample entries
    print("\nSample entries:")
    sample_words = [("我们", "wo men"), ("你好", "ni hao"), ("谢谢", "xie xie"),
                   ("没问题", "mei wen ti"), ("看电视", "kan dian shi"),
                   ("早上好", "zao shang hao"), ("非常好", "fei chang hao")]
    for word, expected_pinyin in sample_words:
        cursor.execute(
            "SELECT pinyin FROM pinyintable WHERE word = ? LIMIT 3",
            (word,)
        )
        results = cursor.fetchall()
        if results:
            pinyins = [r[0] for r in results]
            print(f"  {word}: {', '.join(pinyins)}")
        else:
            print(f"  {word}: NOT FOUND")

    conn.close()

    print(f"\nSummary:")
    print(f"  Deleted: {deleted_count} invalid entries")
    print(f"  Added: {added_count} real common phrases")
    print(f"  Skipped (already exists): {skipped_count} phrases")
    print(f"  Previous total: {current_count}")
    print(f"  New total: {new_count}")

if __name__ == "__main__":
    main()
