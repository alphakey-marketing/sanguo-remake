class_name HelpPanel
extends GamePanel
# 說明頁 (S11c, spec 11 §8 recruitinfo)：新手 5 大主題（介面/戰鬥/賺錢/組隊/飲食）單機觸屏改寫簡介。
# 靜態內容（寫喺呢檔），唔碰 sim；來源 = 原版 recruitinfo.txt / docs/guide 新手教學，精簡為單機適用。

const TOPICS: Array = [
	"介面",
	"戰鬥",
	"賺錢",
	"組隊",
	"飲食",
]

const BODY: Dictionary = {
	"介面": [
		"• 觸屏移動：按實地圖再拖/點，角色行過去。",
		"• 下方 HUD：掟掣開背包 / 角色 / 任務 / 座騎 / 更多。",
		"• 「更多」有登用、官宅、義勇軍、營地、民心、商城、情報冊、結婚等。",
		"• 紅色「戰」掣 = 戰鬥模式開關；關 = 只打怪，開 = NPC 都打得。",
		"• 補品快捷欄可設定自動食/手動食（更多→設定快捷補品欄）。",
		"• 長按地面 = 拾取地面掉落；背包滿會擋。",
	],
	"戰鬥": [
		"• 即時制：點怪行埋去自動打；近身/遠距（弩/弓）按武器。",
		"• 必定打中哋先扣箭（弩/弓）；冇箭出手唔到，去雜貨/木匠補。",
		"• 怪物會逃跑/群攻；boss 每日重生、夜晚有夜怪。",
		"• 術法怪會遠程吟唱，走位可以躲開（睇吟唱線索）。",
		"• 超渡（道士）/急救（武將不）可以復活同伴；叉著 SP 先出招。",
		"• 打人（PK）會扣善惡；殺善 NPC 變罪犯、拒入城。",
	],
	"賺錢": [
		"• 打怪掉寶 / 採集工作（農、獵、伐木…）/ 賣畀商店。",
		"• 魅力、交易專長影響買賣價（買平賣貴）。",
		"• 天地商行：訂閱後腳伕自動存材料、代賣，賺差價。",
		"• 官宅捐獻 / 月俸 / 官令，頭銜越高俸同行動力上限越高。",
		"• 貨金商城：精選商城道具以金兩買（更多→貨金商城）。",
		"• 任務、委託、歷史任務都有錢同經驗獎。",
	],
	"組隊": [
		"• 登用武將做同伴（擂台/問答），同伴幫打、有被動/主動特技。",
		"• 練兵場練歷練要同伴/居民代隊（冇人時可以攞替身）。",
		"• 義勇軍成立後有同伴/部曲帶兵、營地工作同評定會議。",
		"• 結婚配偶可以召喚喺身邊幫手（婚戒無限 50 SP）。",
	],
	"飲食": [
		"• 飲水度低：搭話扣、客棧喝茶回 50 同 MP。",
		"• 食物（燻魚等）回 HP；藥丸散回 MP/SP。",
		"• 客棧休息收金、5 級前新手免費補 HP。",
		"• 吃補品唔限次數，用完即扣背包一件。",
	],
}


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "說明"
	set_tabs(TOPICS)
	tab = 0
	show_topic(0)


func sig() -> String:
	return str(tab)


func set_tab(i: int) -> void:
	tab = i
	super(i)   # 更新掣 state


func _build_body() -> void:
	contrib_about(tab)


func show_topic(i: int) -> void:
	tab = i
	refresh(true)


func contrib_about(i: int) -> void:
	var title: String = String(TOPICS[i])
	body.add_child(lbl("── %s ──" % title, 16, UiTheme.GOLD))
	for line in BODY[title] as Array:
		body.add_child(wrap_lbl(String(line), 13))
	body.add_child(hsep())
	body.add_child(wrap_lbl("（單機觸屏改寫自原版新手教學；其他功能各有對應面板，詳見「更多」選單。）", 12, UiTheme.DIM))