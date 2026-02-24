#!/usr/bin/env python3
"""
检查所有拼音的排序情况
找出常用字排序不合理的拼音
"""

import sys
from collections import defaultdict

# 超高频常用字（应该排在前500）
VERY_COMMON_CHARS = set("""
的一是不了人我在有他这为之大来以个中上们到说国和地也子时道出而要于就下得可你年生自会那后能对着事其里所去行过家十用发天如然作方成者多日都三小军二无同么经法当起与好看学进种将还分此心前面又定见只主没公从
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
""")

def check_pinyin_file(input_file):
    """检查拼音文件的排序情况"""
    print(f"正在读取文件: {input_file}")

    # 按拼音分组
    pinyin_groups = defaultdict(list)

    with open(input_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            parts = line.strip().split('\t')
            if len(parts) == 4:
                word, pinyin, shortcut, hash_val = parts
                if len(word) == 1:  # 只检查单字
                    pinyin_groups[pinyin].append((line_num, word))

            if line_num % 100000 == 0:
                print(f"已处理 {line_num} 行...")

    print(f"\n共找到 {len(pinyin_groups)} 个不同的拼音")

    # 检查每个拼音的排序
    problems = []

    for pinyin in sorted(pinyin_groups.keys()):
        chars = pinyin_groups[pinyin]

        # 找出常用字及其排名
        common_chars_in_group = []
        for rank, char in chars[:50]:  # 只检查前50个
            if char in VERY_COMMON_CHARS:
                common_chars_in_group.append((rank, char))

        # 如果有常用字排在500名之后，记录问题
        if common_chars_in_group:
            max_rank = max(rank for rank, _ in common_chars_in_group)
            if max_rank > 500:
                problems.append({
                    'pinyin': pinyin,
                    'common_chars': common_chars_in_group,
                    'max_rank': max_rank,
                    'all_chars': chars[:20]
                })

    # 显示问题
    if problems:
        print(f"\n发现 {len(problems)} 个拼音存在排序问题：")
        print("=" * 80)

        for problem in sorted(problems, key=lambda x: x['max_rank'], reverse=True):
            print(f"\n拼音: {problem['pinyin']}")
            print(f"  常用字排名过低:")
            for rank, char in problem['common_chars']:
                print(f"    {char}: 第 {rank} 位")
            print(f"  前20个字的排序:")
            for i, (rank, char) in enumerate(problem['all_chars'][:20], 1):
                is_common = "★" if char in VERY_COMMON_CHARS else " "
                print(f"    {i:2d}. {is_common} {char}: 第 {rank} 位")
    else:
        print("\n✓ 所有常用字的排序都正常！")

    # 显示一些示例拼音的排序
    print("\n" + "=" * 80)
    print("示例拼音排序检查：")
    print("=" * 80)

    example_pinyins = ['wo', 'ni', 'ta', 'de', 'shi', 'you', 'zai', 'liang', 'hong', 'hen', 'hao']

    for pinyin in example_pinyins:
        if pinyin in pinyin_groups:
            chars = pinyin_groups[pinyin]
            print(f"\n拼音 '{pinyin}' 的前15个字:")
            for i, (rank, char) in enumerate(chars[:15], 1):
                is_common = "★" if char in VERY_COMMON_CHARS else " "
                print(f"  {i:2d}. {is_common} {char}: 第 {rank} 位")

    return problems

def main():
    input_file = 'Sources/Preparing/Resources/pinyin.txt'

    if len(sys.argv) > 1:
        input_file = sys.argv[1]

    print("=" * 80)
    print("拼音排序全面检查工具")
    print("=" * 80)
    print(f"输入文件: {input_file}")
    print()

    try:
        problems = check_pinyin_file(input_file)

        if problems:
            print(f"\n\n总结: 发现 {len(problems)} 个拼音需要优化")
            print("\n建议: 需要在词频表中补充这些常用字")
        else:
            print("\n\n总结: 所有拼音的排序都符合预期！")

    except Exception as e:
        print(f"\n错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
