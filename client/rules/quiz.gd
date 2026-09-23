class_name RulesQuiz
extends RefCounted
# 理念測驗 (spec 01 §2)【自訂】: 12 題計分 → 五理念之一。決定了就唔可以改。
# 計分: 每題揀 0/1 選項，對應理念 +1；最高分者 = 理念，並列按權重【原】義理>治國>霸權>權謀>隱遁。

const IDEOLOGIES := ["義理", "霸權", "權謀", "隱遁", "治國"]
const TIE_WEIGHT := {"義理": 5, "治國": 4, "霸權": 3, "權謀": 2, "隱遁": 1}


# 計分並定理念。answers = Array[int]，每題 0/1；比題庫長/短都唔怕（截斷/當未答）
static func score(data: GameData, answers: Array) -> Dictionary:
	var qs: Array = data.quiz
	var scores := {}
	for k in IDEOLOGIES:
		scores[k] = 0
	for i in mini(answers.size(), qs.size()):
		var q: Dictionary = qs[i]
		var choice := clampi(int(answers[i]), 0, 1)
		var g: String = String(q["opts"][choice]["g"])
		scores[g] = int(scores[g]) + 1
	var ideology := IDEOLOGIES[0]
	for k in IDEOLOGIES:
		var a := int(scores[k])
		var b := int(scores[ideology])
		if a > b or (a == b and int(TIE_WEIGHT[k]) > int(TIE_WEIGHT[ideology])):
			ideology = k
	return {"scores": scores, "ideology": ideology}


# 答案集合唔合法: 長度要同題庫一樣，每個值 0/1
static func valid_answers(data: GameData, answers: Array) -> bool:
	if answers.size() != (data.quiz as Array).size():
		return false
	for a in answers:
		if int(a) != 0 and int(a) != 1:
			return false
	return true