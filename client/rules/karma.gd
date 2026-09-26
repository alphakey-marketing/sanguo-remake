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


# NPC 買物更貴【原有講無數字】→【自訂】: 罪犯起每階 +10%，中立或以上冇影響
static func price_factor(karma: int) -> float:
	var bad := tier(karma) - 3                # 中立=0，罪犯=1，惡人=2，殺人魔=3
	return 1.0 + maxf(0.0, float(bad)) * 0.1


# ============ S03a 可攻擊 NPC 善惡 (spec 03 §2, 4.1/4.3) ============
# 【原】玩家狀態                    ->  單機化執行位
# ─────────────────────────────────────────────────────────────────
# 殺善玩家: 正/善 -> 直接扣成 -1000    ->  殺善(居民) NPC: 非惡 -> 直接 -1000
# 惡人殺善: 累積 -1000                ->  惡人再殺善居民: 再 -1000
# 善/中立殺紅人(殺人魔玩家): +300      ->  殺紅名(殺人魔) NPC: +300
# 紅殺紅: +300                        ->  殺人魔 NPC 互殺: +300
# 反擊主動攻擊者成功: +100             ->  被 NPC 先攻擊, 成功反殺: +100
const KILL_GOOD_SET := -1000    # 殺善居民 (自己非惡): 直接跌落 -1000
const KILL_GOOD_ADD := -1000    # 惡人再殺善居民: 累積 -1000
const KILL_RED := 300           # 殺紅名(殺人魔) NPC: +300 (善/中立/紅殺紅一致)
const COUNTER_KILL := 100       # 反擊成功 (被 NPC 先攻擊後反殺): +100


# victim = {good: 善居民, red: 紅名殺人魔}（二者其一）→ 新善惡值（夾喺 ±30000）
static func karma_after_kill_npc(karma: int, victim: Dictionary) -> int:
	if bool(victim.get("red", false)):
		return int(clampf(karma + KILL_RED, -30000, 30000))
	if bool(victim.get("good", false)):
		if karma < 0:            # 惡人殺善: 累積
			return int(clampf(karma + KILL_GOOD_ADD, -30000, 30000))
		return int(clampf(KILL_GOOD_SET, -30000, 30000))   # 非惡殺善: 直接 -1000
	return int(clampf(karma, -30000, 30000))


# 反擊成功加成（被先攻擊後反殺，疊加喺 karma_after_kill_npc 之上）
static func counter_kill(karma: int) -> int:
	return int(clampf(karma + COUNTER_KILL, -30000, 30000))
