class_name RulesTips
extends RefCounted
# 新手一次性提示 (每條只彈一次，記喺 ch.tipsSeen)；純文字
const TIPS := {
	"attr": "有未分配屬性點：撳「角色」→ 屬性頁，㩒 ＋ 再「確認分配」。",
	"equip": "背包有武器未裝備：撳「角色」→ 裝備頁換上。",
	"work_zone": "工作區（Lv10 起可做）：撳右下「工作」掣。要先裝備對應工具（許昌工具店買），每次工作扣 10% SP。",
	"death": "倒地唔使驚：等隊友救、自己起身，或者逾時會送返客棧。死亡會扣少少經驗同耐久。",
	"recruit": "登用：調查武將後比試或問答；成功就成為同伴，最多 5 位，登用後隔 1 日先可再調查。",
	"hud_auto": "自動掛機：自動打附近嘅怪；撳「自動」可揀打邊啲怪、自動放招。",
	"hud_skill": "特技掣：用職業特技（開鎖/超渡/隱形/竊聽/透視/融合）。詳情喺「角色」屬性頁。",
	"hud_potion": "快捷補品欄：撳一下即用；撳空格可設定，仲可以設「低於 x% 自動飲」。",
}


static func text_of(key: String) -> String:
	return String(TIPS.get(key, ""))
