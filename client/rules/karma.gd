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


# ============ S03b 天譴 + 城門 (spec 03 §3, §5) ============
# 【原】山洞殺善良玩家 → 天譴即死，還魂丹/超渡冇效；【自訂】單機化:
#   殺善居民(非自衛/非紅名) → 雷劈現有 HP×50% + 傳送返客棧 + 公告「…遭到天譴」，還魂丹無效（有測試）
const TIANQIAN_HP_FRAC := 0.5


# 天譴雷劈後 HP: 現有 HP ×50%，最少留 1（唔會因天譴即死，係趕返客棧嘅懲罰）
static func tianqian_hp(hp: int) -> int:
	return maxi(1, int(float(hp) * TIANQIAN_HP_FRAC))


# 天譴公告文案（世界公告）
static func tianqian_announce(name: String) -> String:
	return "%s因作惡多端遭到天譴" % name


# 天譴無辦法用還魂丹化解（S03c 還魂丹 logic 要檢查呢個 invariant; spec 03 §3「冇得用還魂丹」）
static func tianqian_blocks_revive() -> bool:
	return true


# 殺人魔 (tier 6, ≤ −16001) → 城門衛兵拒入城 (城內服務拒絶)（spec 03 §5）
static func city_banned(karma: int) -> bool:
	return tier(karma) >= 6


# 罪犯及以下 (tier ≥4, ≤ −1001) → 唔接受官令 (spec 03 §5)
static func office_blocked(karma: int) -> bool:
	return tier(karma) >= 4


# 城門衛兵警告文案
static func guard_warn_text(karma: int) -> String:
	return "城門衛兵攔住你：「%s」唔准入城！" % tier_name(karma)
