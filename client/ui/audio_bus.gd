class_name AudioBus
extends Node
# 音效/BGM (素材由 tools/import_orig_assets.py --sets audio 生成，冇檔就靜音)

const MAX_SFX := 6
var _bgm := AudioStreamPlayer.new()
var _sfx: Array[AudioStreamPlayer] = []
var _cache := {}
var bgm_name := ""
var sfx_volume_db := -6.0
var bgm_volume_db := -14.0
var muted := false

func _ready() -> void:
	add_child(_bgm)
	_bgm.volume_db = bgm_volume_db
	for i in MAX_SFX:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)

func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	var p := AssetLib.audio_path(name)
	if p != "" and FileAccess.file_exists(p):
		var o := AudioStreamOggVorbis.load_from_file(p)
		if o != null:
			o.loop = name.begins_with("bgm")
			s = o
	_cache[name] = s
	return s

func play(name: String) -> void:
	if muted:
		return
	var s := _stream(name)
	if s == null:
		return
	for p in _sfx:
		if not p.playing:
			p.stream = s
			p.volume_db = sfx_volume_db
			p.play()
			return

func play_bgm(name: String) -> void:
	if name == bgm_name:
		return
	bgm_name = name
	var s := _stream(name)
	if s == null or muted:
		_bgm.stop()
		return
	_bgm.stream = s
	_bgm.play()

func set_muted(m: bool) -> void:
	muted = m
	if m:
		_bgm.stop()
	else:
		var n := bgm_name
		bgm_name = ""
		play_bgm(n)
