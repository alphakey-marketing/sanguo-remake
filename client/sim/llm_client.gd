class_name LlmClient
extends RefCounted
# OpenRouter 客戶端 (S09d, spec 09 §5)。**只喺呢層處理 key**：存 `user://llm.cfg`（本機）、
# 唔入 sim 存檔、唔入 log/事件。sim 只知 enabled/model（非機密）。
# 網絡傳送用 `transport` Callable 注入（UI 俾 HTTPRequest；測試俾 mock）→ 邏輯層測試唔碰網絡。

const PATH := "user://llm.cfg"

var path := PATH
var cfg: Dictionary = {"key": "", "model": "", "endpoint": ""}
var transport: Callable = Callable()          # func(messages:Array, body:Dictionary, on_done:Callable) -> void
var last_error := ""


func _init(cfg_path: String = PATH) -> void:
	path = cfg_path


func load_cfg() -> Dictionary:
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			cfg = {"key": String((v as Dictionary).get("key", "")), "model": String((v as Dictionary).get("model", "")),
				"endpoint": String((v as Dictionary).get("endpoint", ""))}
	return cfg


func save_cfg(key: String, model: String, endpoint: String = "") -> void:
	cfg = {"key": key, "model": model, "endpoint": endpoint}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cfg))


func clear_key() -> void:
	cfg["key"] = ""
	save_cfg("", String(cfg.get("model", "")), String(cfg.get("endpoint", "")))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func has_key() -> bool:
	return String(cfg.get("key", "")).strip_edges() != ""


func model() -> String:
	return String(cfg.get("model", ""))


func enabled() -> bool:
	return has_key()


# transport 未注入 / 冇 key → 直接 fail（呼叫方 fallback 模板）
func send(data_llm: Dictionary, model_id: String, ctx: Dictionary, on_done: Callable) -> bool:
	last_error = ""
	if not has_key():
		last_error = "no_key"
		on_done.call("", last_error)
		return false
	if not transport.is_valid():
		last_error = "no_transport"
		on_done.call("", last_error)
		return false
	var req := RulesLlm.build_request(data_llm, model_id, ctx, String(cfg.get("key", "")))
	transport.call(req, on_done)
	return true


# UI 用: 真正 HTTPRequest 傳送。回傳 Callable 可以設去 `transport`。
# on_done(text, err)：text = 回應 body 字串；err = "" 成功。
static func http_transport(http: HTTPRequest, timeout_sec: int = 15) -> Callable:
	return func(req: Dictionary, on_done: Callable) -> void:
		http.timeout = float(timeout_sec)
		if http.request_completed.get_connections().is_empty():
			http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
				if code < 200 or code >= 300:
					on_done.call("", "http_%d" % code)
				else:
					on_done.call(body.get_string_from_utf8(), ""), CONNECT_ONE_SHOT)
		var err: int = http.request(String(req.get("url", "")), PackedStringArray(_headers_of(req)),
			HTTPClient.METHOD_POST, JSON.stringify(req.get("body", {})))
		if err != OK:
			on_done.call("", "http_error")


static func _headers_of(req: Dictionary) -> Array:
	var out: Array = []
	var h = req.get("headers", {})
	if h is Dictionary:
		for k in h:
			out.append("%s: %s" % [String(k), String(h[k])])
	return out