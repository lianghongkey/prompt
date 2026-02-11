#!/usr/bin/env python3
"""
Generate simplified Mandarin Chinese pinyin lexicon.
Converts traditional characters to simplified and filters for Mandarin only.
"""

import subprocess
import sys

# Try to install xpinyin and opencc if not available
try:
    from xpinyin import Pinyin
    import opencc
except ImportError as e:
    print(f"Installing missing dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "xpinyin", "opencc-python-reimplemented"])
    from xpinyin import Pinyin
    import opencc

def generate_simplified_lexicon():
    """Generate a simplified Mandarin Chinese pinyin lexicon."""
    # Initialize converters
    pinyin_converter = Pinyin()
    cc = opencc.OpenCC('t2s')  # Traditional to Simplified

    # Common Mandarin multi-character words (词组)
    # These are essential for continuous pinyin input
    mandarin_words = [
        # Personal pronouns
        "我们", "你们", "他们", "她们", "咱们", "自己", "大家",
        # Common verbs
        "是", "有", "在", "去", "来", "做", "说", "看", "听", "吃", "喝",
        "可以", "能够", "应该", "需要", "想要", "喜欢", "爱", "知道", "认为", "觉得",
        "会", "能", "要", "想", "让", "叫", "请", "帮", "给", "拿",
        # Time and place
        "现在", "以后", "以前", "今天", "明天", "昨天", "时候", "地方", "这里", "那里",
        "中国", "国家", "世界", "城市", "家", "学校", "公司", "工作",
        # Common adjectives
        "好", "大", "小", "多", "少", "新", "老", "长", "短", "高", "低",
        "很多", "比较", "非常", "特别", "真的", "当然", "肯定", "可能",
        # Common nouns
        "东西", "事情", "问题", "方法", "时候", "朋友", "人", "孩子", "学生", "老师",
        "时间", "钱", "年", "月", "日", "天", "小时", "分钟",
        # Common phrases
        "因为", "所以", "但是", "然后", "而且", "或者", "如果", "虽然", "可是", "不过",
        "一下", "一起", "一样", "一样", "这种", "那种", "这个", "那个", "什么", "怎么",
        # Numbers and quantities
        "一个", "两个", "三个", "几个", "第一", "第二", "一些", "所有", "每个",
        # Common expressions
        "你好", "谢谢", "对不起", "没关系", "再见", "请问", "可以吗", "好吗",
        # Government and society
        "人民", "政府", "社会", "发展", "经济", "文化", "教育", "科技", "医疗", "交通",
        # Common words (2-4 characters)
        "了解", "认为", "已经", "还是", "或者", "因为", "这样", "那样", "怎样",
        "出来", "进去", "回来", "过去", "起来", "下去", "上来", "下去",
        "看见", "听到", "找到", "得到", "买到", "做到", "学到", "想到",
        "重要", "主要", "只要", "只要", "需要", "必须", "一定", "当然",
        "开始", "结束", "完成", "进行", "继续", "停止", "准备", "决定",
        "表示", "认为", "以为", "觉得", "感觉", "发现", "出现", "实现",
        "提高", "增加", "减少", "降低", "改变", "保持", "维持", "建立",
        "中心", "公司", "单位", "部门", "组织", "团体", "机构", "系统",
        "会议", "活动", "项目", "计划", "方案", "目标", "任务", "工作",
        "产品", "服务", "质量", "效果", "结果", "成绩", "进步", "发展",
        "学习", "研究", "分析", "讨论", "交流", "沟通", "联系", "合作",
        "电话", "邮件", "信息", "消息", "通知", "消息", "新闻", "报道",
        "网络", "网站", "平台", "软件", "硬件", "系统", "程序", "应用",
        "手机", "电脑", "设备", "工具", "方法", "技术", "能力", "水平",
        "经验", "知识", "技能", "能力", "条件", "情况", "状况", "状态",
        "环境", "条件", "因素", "原因", "结果", "影响", "作用", "效果",
        "生活", "工作", "学习", "家庭", "朋友", "同事", "同学", "邻居",
        "父母", "孩子", "子女", "兄弟", "姐妹", "夫妻", "先生", "女士",
        "上午", "下午", "晚上", "早上", "中午", "夜里", "白天", "晚上",
        "星期", "周末", "月底", "年底", "年初", "月底", "季节", "假期",
        "春天", "夏天", "秋天", "冬天", "天气", "气候", "温度", "环境",
        "颜色", "红色", "蓝色", "绿色", "黄色", "黑色", "白色", "颜色",
        "衣服", "鞋子", "裤子", "衬衫", "外套", "裙子", "帽子", "手套",
        "食品", "水果", "蔬菜", "肉类", "鱼类", "鸡肉", "猪肉", "牛肉",
        "米饭", "面条", "面包", "牛奶", "豆浆", "果汁", "水", "茶",
        "房间", "客厅", "卧室", "厨房", "厕所", "浴室", "阳台", "门口",
        "汽车", "公交", "地铁", "火车", "飞机", "自行车", "摩托车", "车辆",
        "医院", "银行", "商店", "超市", "餐厅", "酒店", "旅馆", "市场",
        "公园", "广场", "街道", "马路", "路口", "车站", "机场", "港口",
        "书", "报纸", "杂志", "文章", "小说", "故事", "新闻", "消息",
        "电影", "电视", "广播", "音乐", "歌曲", "游戏", "运动", "比赛",
        "快乐", "高兴", "开心", "幸福", "满意", "舒服", "愉快", "兴奋",
        "伤心", "难过", "痛苦", "烦恼", "担心", "害怕", "紧张", "着急",
        "美丽", "漂亮", "英俊", "可爱", "聪明", "智慧", "勇敢", "坚强",
        "善良", "友好", "热情", "礼貌", "客气", "真诚", "诚实", "可靠",
        # Common 3-character words
        "不可能", "不知道", "不好意思", "没问题", "没关系", "可以说", "很重要",
        "图书馆", "电影院", "火车站", "飞机场", "公共汽车", "出租汽车", "自行车道",
        "大学生", "研究生", "中学生", "小学生", "老师好", "同学们", "朋友们",
        "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日",
        "大多数", "很少", "很多", "更好", "最好", "更重要", "更便宜",
        # Common 4-character words
        "中华人民共和国", "人民政府", "社会稳定", "经济发展", "文化交流", "科技进步",
        "非常重要", "十分感谢", "热烈欢迎", "衷心感谢", "共同努力", "团结合作",
    ]

    # Read existing single character entries
    existing_pinyin = set()
    pinyin_txt_path = "/Users/colin/develop/TypeDuck-Mac/Preparing/Sources/Preparing/Resources/pinyin.txt"
    try:
        with open(pinyin_txt_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if '\t' in line:
                    word = line.split('\t')[0]
                    existing_pinyin.add(word)
    except FileNotFoundError:
        pass

    # Generate new entries
    new_entries = []
    for word in mandarin_words:
        # Convert to simplified (in case it's traditional)
        simplified_word = cc.convert(word)

        # Skip if already exists
        if simplified_word in existing_pinyin:
            continue

        # Generate pinyin
        pinyin_str = pinyin_converter.get_pinyin(simplified_word, splitter=' ')
        new_entries.append(f"{simplified_word}\t{pinyin_str}")

    return new_entries

def main():
    print("Generating simplified Mandarin Chinese pinyin lexicon...")
    new_entries = generate_simplified_lexicon()

    # Append to pinyin.txt
    pinyin_txt_path = "/Users/colin/develop/TypeDuck-Mac/Preparing/Sources/Preparing/Resources/pinyin.txt"
    with open(pinyin_txt_path, 'a', encoding='utf-8') as f:
        for entry in new_entries:
            f.write(entry + '\n')

    print(f"Added {len(new_entries)} simplified Mandarin entries to pinyin.txt")
    print(f"\nExample entries:")
    for entry in new_entries[:20]:
        print(f"  {entry}")

if __name__ == "__main__":
    main()
