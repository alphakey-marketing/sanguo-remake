class_name RulesHelpIntro
extends RefCounted
# 首次開面板簡介 (S11d, spec 11 §B4)：面板 class 名 -> 一兩句簡介。開過（ch.helpSeen）就唔再彈。

const INTRO: Dictionary = {
	"BagPanel": "背包：撳物品可以用、裝備、丟、賣。背包滿咗會擋住拾取。",
	"CharPanel": "角色：睇屬性、專長、裝備同稱號；升級加嘅點數喺呢度分配。",
	"QuestPanel": "任務：睇進行中任務同提示。有前置條件嘅任務會寫明要求。",
	"MountPanel": "座騎：買馬、騎乘、改名、飼養同繁衍；跑馬燈可以玩賭馬。",
	"WarBeastPanel": "戰騎：出戰時同你一齊打，餵養升級。",
	"OfficePanel": "官宅：領官令、月俸同頭銜升遷，高頭銜俸祿同行動力上限更高。",
	"MilitiaPanel": "義勇軍：招兵買馬，部曲同同伴幫你打。",
	"CampPanel": "營地：庫存、工作同評定會議都喺呢度。",
	"CivicPanel": "民心/法令：佔城之後先有得調稅率同法令。",
	"CraftPanel": "生產：揀配方，備齊材料就做。做多咗技能升級，可解鎖進階配方。",
	"ShopPanel": "商店：買平賣貴，魅力同交易專長可以減價。",
	"MallPanel": "貨金商城：用金兩買精選道具，價錢已按單機改過。",
	"RecruitPanel": "登用：擂台或問答通過先登用到武將；成敗睇魅力、政治、等級同頭銜。",
	"MarriagePanel": "結婚：向合適對象求婚，配偶可以召喚幫手。",
	"LlmPanel": "LLM 設定/對話：填 API 後 NPC 可以自由傾偈；唔填都有預設對白。",
	"RumorPanel": "情報冊/傳聞：竊聽線索同各城傳聞。",
	"MapPanel": "地圖：睇世界節點，撳驛站可以傳送。",
	"UnlockPanel": "開鎖：揀鎖匠道具，成功率睇技能同運氣。",
	"StealthPanel": "潛行：進入潛行避開怪物視線。",
	"DropPanel": "掉寶表：查邊隻怪掉乜。",
}


static func text_for(panel_class: String) -> String:
	return String(INTRO.get(panel_class, ""))


static func should_show(seen: Array, panel_class: String) -> bool:
	return text_for(panel_class) != "" and not seen.has(panel_class)
