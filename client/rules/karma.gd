class_name RulesKarma
# 善惡七階【原】(攻略 §4): 純函數

const TIERS := [
	{"min": 16001, "name": "大英雄"},
	{"min": 8001, "name": "善人"},
	{"min": 1001, "name": "好人"},
	{"min": -1000, "name": "中立"},
	{"min": -8000, "name": "罪犯"},
	{"min": -16000, "name": "惡人"},
	{"min": -30000, "name": "殺人魔"},
]


# 回傳階級 0(大英雄)~6(殺人魔)
static func tier(karma: int) -> int:
	for i in TIERS.size():
		if karma >= int(TIERS[i]["min"]):
			return i
	return TIERS.size() - 1


static func tier_name(karma: int) -> String:
	return TIERS[tier(karma)]["name"]
