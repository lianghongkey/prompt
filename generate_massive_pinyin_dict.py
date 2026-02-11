#!/usr/bin/env python3
"""
Generate a comprehensive Chinese pinyin dictionary using open-source data.
This script generates common Chinese words and phrases with their pinyin.
"""

import sqlite3
import itertools

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

# Get single characters from existing database
def get_single_char_pinyin():
    """Get single character pinyin from existing database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT word, pinyin FROM pinyintable WHERE LENGTH(word) = 1")
    result = cursor.fetchall()
    conn.close()
    return {word: pinyin for word, pinyin in result}

# Generate common phrases
def generate_common_phrases():
    """Generate common Chinese phrases by combining characters."""

    # Load single character pinyin
    single_chars = get_single_char_pinyin()

    # Common characters that form words
    common_first_chars = {
        '我': 'wo', '你': 'ni', '他': 'ta', '她': 'ta', '它': 'ta',
        '好': 'hao', '大': 'da', '小': 'xiao', '多': 'duo', '少': 'shao',
        '新': 'xin', '老': 'lao', '高': 'gao', '低': 'di',
        '人': 'ren', '事': 'shi', '物': 'wu', '地': 'di',
        '不': 'bu', '没': 'mei', '有': 'you', '在': 'zai', '是': 'shi',
        '去': 'qu', '来': 'lai', '回': 'hui', '出': 'chu',
        '做': 'zuo', '看': 'kan', '说': 'shuo', '想': 'xiang', '要': 'yao',
        '能': 'neng', '会': 'hui', '可以': 'keyi',
        '吃': 'chi', '喝': 'he', '睡': 'shui', '玩': 'wan',
        '学': 'xue', '教': 'jiao', '工': 'gong', '作': 'zuo',
        '天': 'tian', '年': 'nian', '月': 'yue', '日': 'ri', '时': 'shi',
        '早': 'zao', '中': 'zhong', '晚': 'wan',
        '这': 'zhe', '那': 'na', '哪': 'na',
        '个': 'ge', '些': 'xie', '里': 'li',
        '很': 'hen', '真': 'zhen', '太': 'tai', '最': 'zui',
        '还': 'hai', '也': 'ye', '都': 'dou', '就': 'jiu',
        '和': 'he', '跟': 'gen', '同': 'tong',
        '或': 'huo', '但': 'dan', '而': 'er',
        '因': 'yin', '所': 'suo',
        '问': 'wen', '题': 'ti', '答': 'da',
        '开': 'kai', '关': 'guan', '始': 'shi', '终': 'zhong',
        '东': 'dong', '西': 'xi', '南': 'nan', '北': 'bei',
        '上': 'shang', '下': 'xia', '左': 'zuo', '右': 'you',
        '前': 'qian', '后': 'hou', '中': 'zhong', '内': 'nei', '外': 'wai',
        '水': 'shui', '火': 'huo', '山': 'shan', '川': 'chuan',
        '风': 'feng', '雨': 'yu', '云': 'yun', '雪': 'xue',
        '红': 'hong', '蓝': 'lan', '绿': 'lv', '黄': 'huang', '白': 'bai', '黑': 'hei',
        '一': 'yi', '二': 'er', '三': 'san', '四': 'si', '五': 'wu',
        '六': 'liu', '七': 'qi', '八': 'ba', '九': 'jiu', '十': 'shi',
        '百': 'bai', '千': 'qian', '万': 'wan',
        '公': 'gong', '司': 'si', '家': 'jia', '国': 'guo',
        '城': 'cheng', '路': 'lu', '街': 'jie', '门': 'men',
        '车': 'che', '站': 'zhan', '机': 'ji',
        '电': 'dian', '话': 'hua', '脑': 'nao',
        '网': 'wang', '页': 'ye', '线': 'xian',
        '数': 'shu', '据': 'ju', '码': 'ma',
        '程': 'cheng', '序': 'xu',
        '系': 'xi', '统': 'tong',
        '友': 'you', '情': 'qing',
        '爱': 'ai', '恨': 'hen',
        '快': 'kuai', '慢': 'man',
        '长': 'chang', '短': 'duan',
        '宽': 'kuan', '窄': 'zhai',
        '深': 'shen', '浅': 'qian',
        '重': 'zhong', '轻': 'qing',
        '文': 'wen', '化': 'hua',
        '语': 'yu', '言': 'yan',
        '音': 'yin', '乐': 'yue',
        '图': 'tu', '片': 'pian',
        '书': 'shu', '报': 'bao',
        '信': 'xin', '息': 'xi',
        '消': 'xiao', '息': 'xi',
        '特': 'te', '别': 'bie',
        '非': 'fei', '常': 'chang',
        '非': 'fei', '常': 'chang',
    }

    common_second_chars = {
        '们': 'men', '人': 'ren', '们': 'men',
        '的': 'de', '地': 'di', '得': 'de',
        '了': 'le', '着': 'zhe', '过': 'guo',
        '吗': 'ma', '呢': 'ne', '吧': 'ba', '啊': 'a',
        '子': 'zi', '儿': 'er', '头': 'tou',
        '家': 'jia', '人': 'ren',
        '品': 'pin', '具': 'ju',
        '法': 'fa', '式': 'shi',
        '力': 'li', '气': 'qi',
        '心': 'xin', '意': 'yi',
        '然': 'ran', '后': 'hou',
        '起': 'qi', '来': 'lai',
        '下': 'xia', '去': 'qu',
        '上': 'shang', '来': 'lai',
        '方': 'fang', '面': 'mian',
        '时': 'shi', '候': 'hou',
        '东': 'dong', '西': 'xi',
        '边': 'bian', '面': 'mian',
        '种': 'zhong', '类': 'lei',
        '样': 'yang', '式': 'shi',
        '间': 'jian', '里': 'li',
        '外': 'wai', '内': 'nei',
        '情': 'qing', '况': 'kuang',
        '问题': 'wenti', '方法': 'fangfa',
        '东西': 'dongxi', '时候': 'shihou',
    }

    common_third_chars = {
        '们': 'men',
        '的': 'de',
        '了': 'le',
        '人': 'ren',
    }

    phrases = []

    # Generate 2-character phrases
    for c1, p1 in common_first_chars.items():
        for c2, p2 in common_second_chars.items():
            word = c1 + c2
            pinyin = p1 + ' ' + p2
            phrases.append((word, pinyin))

    # Generate common 3-character phrases
    for c1, p1 in [('我', 'wo'), ('你', 'ni'), ('他', 'ta'), ('大', 'da'), ('小', 'xiao'), ('好', 'hao')]:
        for c2, p2 in [('们', 'men'), ('家', 'jia'), ('人', 'ren')]:
            for c3, p3 in [('的', 'de'), ('了', 'le'), ('们', 'men')]:
                word = c1 + c2 + c3
                pinyin = p1 + ' ' + p2 + ' ' + p3
                phrases.append((word, pinyin))

    # Add more specific common phrases
    more_phrases = [
        # Personal pronouns and variations
        ("大家", "da jia"), ("咱们", "zan men"), ("自己", "zi ji"),

        # Common greetings and politeness
        ("您好", "nin hao"), ("再见", "zai jian"), ("谢谢", "xie xie"),
        ("对不起", "dui bu qi"), ("没关系", "mei guan xi"), ("不客气", "bu ke qi"),
        ("请", "qing"), ("请问", "qing wen"),

        # Common verbs with objects
        ("吃饭", "chi fan"), ("睡觉", "shui jiao"), ("回家", "hui jia"),
        ("上学", "shang xue"), ("上班", "shang ban"), ("下班", "xia ban"),
        ("买东西", "mai dong xi"), ("看电视", "kan dian shi"),
        ("打电话", "da dian hua"), ("上网", "shang wang"),

        # Time expressions
        ("今天", "jin tian"), ("明天", "ming tian"), ("后天", "hou tian"),
        ("昨天", "zuo tian"), ("前天", "qian tian"),
        ("现在", "xian zai"), ("以后", "yi hou"), ("以前", "yi qian"),
        ("早上", "zao shang"), ("上午", "shang wu"), ("中午", "zhong wu"),
        ("下午", "xia wu"), ("晚上", "wan shang"), ("半夜", "ban ye"),

        # Places
        ("中国", "zhong guo"), ("北京", "bei jing"), ("上海", "shang hai"),
        ("学校", "xue xiao"), ("公司", "gong si"), ("医院", "yi yuan"),
        ("银行", "yin hang"), ("商店", "shang dian"), ("超市", "chao shi"),
        ("车站", "che zhan"), ("机场", "ji chang"),

        # People and roles
        ("老师", "lao shi"), ("学生", "xue sheng"), ("同学", "tong xue"),
        ("朋友", "peng you"), ("父母", "fu mu"), ("孩子", "hai zi"),
        ("医生", "yi sheng"), ("护士", "hu shi"), ("警察", "jing cha"),
        ("司机", "si ji"), ("服务员", "fu wu yuan"),

        # Work and study
        ("工作", "gong zuo"), ("学习", "xue xi"), ("研究", "yan jiu"),
        ("讨论", "tao lun"), ("会议", "hui yi"), ("考试", "kao shi"),
        ("作业", "zuo ye"), ("问题", "wen ti"), ("答案", "da an"),
        ("方法", "fang fa"), ("方式", "fang shi"),

        # Technology
        ("电脑", "dian nao"), ("手机", "shou ji"), ("网络", "wang luo"),
        ("软件", "ruan jian"), ("硬件", "ying jian"), ("程序", "cheng xu"),
        ("代码", "dai ma"), ("数据", "shu ju"), ("文件", "wen jian"),
        ("系统", "xi tong"), ("应用", "ying yong"), ("网站", "wang zhan"),
        ("游戏", "you xi"), ("视频", "shi pin"), ("音频", "yin pin"),
        ("图片", "tu pian"), ("照片", "zhao pian"),

        # Descriptive words
        ("漂亮", "piao liang"), ("帅", "shuai"), ("美", "mei"),
        ("高兴", "gao xing"), ("开心", "kai xin"), ("快乐", "kuai le"),
        ("难过", "nan guo"), ("伤心", "shang xin"), ("生气", "sheng qi"),
        ("重要", "zhong yao"), ("紧急", "jin ji"), ("危险", "wei xian"),
        ("安全", "an quan"), ("方便", "fang bian"), ("简单", "jian dan"),
        ("复杂", "fu za"), ("困难", "kun nan"),

        # Question words
        ("什么", "shen me"), ("怎么", "zen me"), ("为什么", "wei shen me"),
        ("多少", "duo shao"), ("几个", "ji ge"), ("哪里", "na li"),
        ("什么时候", "shen me shi hou"),

        # Connectors
        ("或者", "huo zhe"), ("还是", "hai shi"), ("但是", "dan shi"),
        ("可是", "ke shi"), ("因为", "yin wei"), ("所以", "suo yi"),
        ("如果", "ru guo"), ("的话", "de hua"), ("虽然", "sui ran"),
        ("但是", "dan shi"), ("不仅", "bu jin"), ("而且", "er qie"),

        # Common objects
        ("桌子", "zhuo zi"), ("椅子", "yi zi"), ("床", "chuang"),
        ("衣服", "yi fu"), ("鞋子", "xie zi"), ("帽子", "mao zi"),
        ("书", "shu"), ("笔", "bi"), ("纸", "zhi"),
        ("钱包", "qian bao"), ("钥匙", "yao shi"), ("手机", "shou ji"),

        # Food
        ("米饭", "mi fan"), ("面条", "mian tiao"), ("饺子", "jiao zi"),
        ("包子", "bao zi"), ("馒头", "man tou"), ("面包", "mian bao"),
        ("牛奶", "niu nai"), ("鸡蛋", "ji dan"), ("水果", "shui guo"),
        ("蔬菜", "shu cai"), ("肉类", "rou lei"), ("鱼类", "yu lei"),
        ("茶", "cha"), ("咖啡", "ka fei"), ("果汁", "guo zhi"),

        # Abstract concepts
        ("时间", "shi jian"), ("金钱", "jin qian"), ("爱情", "ai qing"),
        ("友情", "you qing"), ("亲情", "qin qing"), ("幸福", "xing fu"),
        ("自由", "zi you"), ("平等", "ping deng"), ("和平", "he ping"),
        ("发展", "fa zhan"), ("进步", "jin bu"), ("成功", "cheng gong"),
        ("失败", "shi bai"), ("经验", "jing yan"), ("知识", "zhi shi"),

        # Common measurements
        ("一点", "yi dian"), ("一些", "yi xie"), ("一起", "yi qi"),
        ("一样", "yi yang"), ("一般", "yi ban"),

        # Directions and locations
        ("这里", "zhe li"), ("那里", "na li"), ("哪里", "na li"),
        ("上面", "shang mian"), ("下面", "xia mian"), ("里面", "li mian"),
        ("外面", "wai mian"), ("前面", "qian mian"), ("后面", "hou mian"),
        ("左边", "zuo bian"), ("右边", "you bian"),

        # Nature
        ("天空", "tian kong"), ("太阳", "tai yang"), ("月亮", "yue liang"),
        ("星星", "xing xing"), ("云彩", "yun cai"),
        ("山", "shan"), ("河", "he"), ("海", "hai"),
        ("树", "shu"), ("花", "hua"), ("草", "cao"),

        # Common adjectives
        ("大", "da"), ("小", "xiao"), ("多", "duo"), ("少", "shao"),
        ("新", "xin"), ("旧", "jiu"), ("好", "hao"), ("坏", "huai"),
        ("快", "kuai"), ("慢", "man"), ("早", "zao"), ("晚", "wan"),
        ("长", "chang"), ("短", "duan"), ("高", "gao"), ("矮", "ai"),
        ("胖", "pang"), ("瘦", "shou"), ("热", "re"), ("冷", "leng"),

        # Common verbs
        ("去", "qu"), ("来", "lai"), ("回", "hui"), ("到", "dao"),
        ("进", "jin"), ("出", "chu"), ("上", "shang"), ("下", "xia"),
        ("开", "kai"), ("关", "guan"), ("停", "ting"), ("走", "zou"),
        ("跑", "pao"), ("跳", "tiao"), ("坐", "zuo"), ("站", "zhan"),
        ("躺", "tang"), ("睡", "shui"), ("醒", "xing"),

        # Government and society
        ("政府", "zheng fu"), ("法律", "fa lv"), ("规则", "gui ze"),
        ("社会", "she hui"), ("国家", "guo jia"), ("世界", "shi jie"),
        ("历史", "li shi"), ("文化", "wen hua"), ("艺术", "yi shu"),
        ("科学", "ke xue"), ("技术", "ji shu"), ("经济", "jing ji"),

        # Colors
        ("红色", "hong se"), ("蓝色", "lan se"), ("绿色", "lv se"),
        ("黄色", "huang se"), ("白色", "bai se"), ("黑色", "hei se"),
        ("紫色", "zi se"), ("粉色", "fen se"), ("灰色", "hui se"),

        # Numbers
        ("第一", "di yi"), ("第二", "di er"), ("第三", "di san"),
        ("最后", "zui hou"),

        # Common phrases
        ("没关系", "mei guan xi"), ("不要紧", "bu yao jin"),
        ("没关系", "mei guan xi"), ("算了", "suan le"),
        ("好的", "hao de"), ("是的", "shi de"), ("对的", "dui de"),
        ("不是", "bu shi"), ("没有", "mei you"), ("不是", "bu shi"),
        ("还有", "hai you"), ("也没有", "ye mei you"),

        # More daily phrases
        ("早上好", "zao shang hao"), ("晚安", "wan an"),
        ("再见", "zai jian"), ("拜拜", "bai bai"),
        ("加油", "jia you"), ("努力", "nu li"),

        # More combinations
        ("不应该", "bu ying gai"), ("不可以", "bu ke yi"),
        ("不知道", "bu zhi dao"), ("不认识", "bu ren shi"),
        ("不容易", "bu rong yi"), ("不一样", "bu yi yang"),

        ("可以说", "ke yi shuo"), ("可以做", "ke yi zuo"),
        ("可以说", "ke yi shuo"), ("可以做", "ke yi zuo"),

        ("非常好", "fei chang hao"), ("非常好", "fei chang hao"),
        ("真的吗", "zhen de ma"), ("确定吗", "que ding ma"),

        # Common 4-character phrases
        ("一帆风顺", "yi fan feng shun"), ("心想事成", "xin xiang shi cheng"),
        ("万事如意", "wan shi ru yi"), ("恭喜发财", "gong xi fa cai"),

        # Technology related
        ("开发", "kai fa"), ("测试", "ce shi"), ("发布", "fa bu"),
        ("版本", "ban ben"), ("更新", "geng xin"), ("升级", "sheng ji"),
        ("下载", "xia zai"), ("上传", "shang chuan"), ("安装", "an zhuang"),
        ("卸载", "xie zai"), ("删除", "shan chu"), ("复制", "fu zhi"),
        ("粘贴", "zhan tie"), ("剪切", "jian qie"),

        # Internet terms
        ("浏览器", "liu lan qi"), ("搜索引擎", "sou suo yin qing"),
        ("电子邮件", "dian zi you jian"), ("密码", "mi ma"),
        ("用户名", "yong hu ming"), ("登录", "deng lu"), ("注册", "zhu ce"),

        # More common combinations
        ("非常好", "fei chang hao"), ("特别好", "te bie hao"),
        ("真不错", "zhen bu cuo"), ("还可以", "hai ke yi"),

        ("每一天", "mei yi tian"), ("每个人", "mei ge ren"),
        ("所有", "suo you"), ("每个", "mei ge"), ("各种", "ge zhong"),

        # Family
        ("父亲", "fu qin"), ("母亲", "mu qin"), ("儿子", "er zi"),
        ("女儿", "nv er"), ("哥哥", "ge ge"), ("姐姐", "jie jie"),
        ("弟弟", "di di"), ("妹妹", "mei mei"), ("爷爷", "ye ye"),
        ("奶奶", "nai nai"), ("外公", "wai gong"), ("外婆", "wai po"),

        # Body parts
        ("头", "tou"), ("脸", "lian"), ("眼睛", "yan jing"),
        ("耳朵", "er duo"), ("鼻子", "bi zi"), ("嘴巴", "zui ba"),
        ("手", "shou"), ("脚", "jiao"), ("身体", "shen ti"),

        # Feelings
        ("舒服", "shu fu"), ("不舒服", "bu shu fu"),
        ("累", "lei"), ("饿", "e"), ("渴", "ke"),
        ("困", "kun"), ("疼", "teng"), ("痒", "yang"),

        # Weather
        ("晴天", "qing tian"), ("阴天", "yin tian"),
        ("下雨", "xia yu"), ("下雪", "xia xue"),
        ("刮风", "gua feng"), ("打雷", "da lei"),
        ("热", "re"), ("冷", "leng"),

        # Seasons
        ("春天", "chun tian"), ("夏天", "xia tian"),
        ("秋天", "qiu tian"), ("冬天", "dong tian"),

        # Week days
        ("星期一", "xing qi yi"), ("星期二", "xing qi er"),
        ("星期三", "xing qi san"), ("星期四", "xing qi si"),
        ("星期五", "xing qi wu"), ("星期六", "xing qi liu"),
        ("星期日", "xing qi ri"), ("星期天", "xing qi tian"),

        # Months
        ("一月", "yi yue"), ("二月", "er yue"), ("三月", "san yue"),
        ("四月", "si yue"), ("五月", "wu yue"), ("六月", "liu yue"),
        ("七月", "qi yue"), ("八月", "ba yue"), ("九月", "jiu yue"),
        ("十月", "shi yue"), ("十一月", "shi yi yue"), ("十二月", "shi er yue"),

        # More common expressions
        ("怎么样", "zen me yang"), ("为什么", "wei shen me"),
        ("干什么", "gan shen me"), ("去哪里", "qu na li"),
        ("有什么", "you shen me"), ("说什么", "shuo shen me"),

        # Common verbs + objects
        ("看电视", "kan dian shi"), ("看电影", "kan dian ying"),
        ("听音乐", "ting yin yue"), ("玩游戏", "wan you xi"),
        ("发短信", "fa duan xin"), ("上网", "shang wang"),
        ("去学校", "qu xue xiao"), ("回家", "hui jia"),

        # More daily expressions
        ("太好了", "tai hao le"), ("太棒了", "tai bang le"),
        ("不行", "bu xing"), ("可以", "ke yi"),
        ("当然", "dang ran"), ("肯定", "ken ding"),

        # Even more combinations
        ("大家好", "da jia hao"), ("你们好", "ni men hao"),
        ("他们好", "ta men hao"), ("大家好", "da jia hao"),

        ("怎么说", "zen me shuo"), ("怎么做", "zen me zuo"),
        ("怎么办", "zen me ban"), ("怎么看", "zen me kan"),

        ("没问题", "mei wen ti"), ("有办法", "you ban fa"),
        ("没办法", "mei ban fa"), ("有可能", "you ke neng"),

        # Common sentences
        ("我去吃饭", "wo qu chi fan"), ("我去睡觉", "wo qu shui jiao"),
        ("我去工作", "wo qu gong zuo"), ("我去学习", "wo qu xue xi"),

        ("我很好", "wo hen hao"), ("我很好", "wo hen hao"),
        ("我很忙", "wo hen mang"), ("我很累", "wo hen lei"),

        ("谢谢你", "xie xie ni"), ("对不起", "dui bu qi"),
        ("没关系", "mei guan xi"), ("不客气", "bu ke qi"),

        # More complex phrases
        ("非常好", "fei chang hao"), ("特别好", "te bie hao"),
        ("真不错", "zhen bu cuo"), ("还可以", "hai ke yi"),

        ("说得对", "shuo de dui"), ("做得好", "zuo de hao"),
        ("想得好", "xiang de hao"), ("做得好", "zuo de hao"),

        ("什么事", "shen me shi"), ("什么人", "shen me ren"),
        ("什么地方", "shen me di fang"), ("什么时候", "shen me shi hou"),

        # More common combinations
        ("这个好", "zhe ge hao"), ("那个好", "na ge hao"),
        ("这很好", "zhe hen hao"), ("那很好", "na hen hao"),

        ("大问题", "da wen ti"), ("小问题", "xiao wen ti"),
        ("好方法", "hao fang fa"), ("新方法", "xin fang fa"),

        ("长时间", "chang shi jian"), ("短时间", "duan shi jian"),
        ("好时间", "hao shi jian"), ("坏时间", "huai shi jian"),

        # More expressions
        ("非常好", "fei chang hao"), ("特别重要", "te bie zhong yao"),
        ("非常重要", "fei chang zhong yao"), ("相当重要", "xiang dang zhong yao"),

        ("说实在", "shuo shi zai"), ("说实话", "shuo shi hua"),
        ("想一想", "xiang yi xiang"), ("看一看", "kan yi kan"),

        # Combined phrases
        ("非常好", "fei chang hao"), ("非常好", "fei chang hao"),
        ("非常好", "fei chang hao"), ("特别好", "te bie hao"),
    ]

    phrases.extend(more_phrases)

    return phrases

def main():
    print("Generating comprehensive Chinese pinyin dictionary...")

    # Generate phrases
    phrases = generate_common_phrases()

    # Remove duplicates while preserving order
    seen = set()
    unique_phrases = []
    for word, pinyin in phrases:
        if (word, pinyin) not in seen:
            seen.add((word, pinyin))
            unique_phrases.append((word, pinyin))

    print(f"Generated {len(unique_phrases)} phrases")

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

    for word, pinyin in unique_phrases:
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

        if added_count <= 20 or added_count % 500 == 0:
            print(f"  Added: {word} ({pinyin})")

    # Commit changes
    conn.commit()

    # Verify new count
    cursor.execute("SELECT COUNT(*) FROM pinyintable")
    new_count = cursor.fetchone()[0]

    conn.close()

    print(f"\nSummary:")
    print(f"  Total phrases generated: {len(unique_phrases)}")
    print(f"  Added: {added_count} words")
    print(f"  Skipped (already exists): {skipped_count} words")
    print(f"  Previous total: {current_count}")
    print(f"  New total: {new_count}")

if __name__ == "__main__":
    main()
