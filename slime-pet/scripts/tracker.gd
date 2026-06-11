extends Node
## 背景追蹤器 (autoload: Tracker)
## 定時取樣目前前景視窗（混合模式：平常只記文字，截圖選用），寫入 Store。

signal sample_taken(sample: Dictionary)
signal state_changed(running: bool)

const SHOT_DIR := "user://screenshots"

var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)
	apply_config()
	if Config.tracking_enabled:
		start()

func apply_config() -> void:
	_timer.wait_time = float(max(5, Config.capture_interval_sec))
	if not _timer.is_stopped():
		# 立即套用新的間隔
		_timer.start()

func is_running() -> bool:
	return not _timer.is_stopped()

func start() -> void:
	Config.tracking_enabled = true
	_timer.start()
	_on_tick()                # 啟動立刻取一筆
	state_changed.emit(true)

func stop() -> void:
	Config.tracking_enabled = false
	_timer.stop()
	state_changed.emit(false)

func toggle() -> void:
	if is_running():
		stop()
	else:
		start()

func _on_tick() -> void:
	var info := Platform.get_active_window()
	var t := Time.get_time_dict_from_system()
	var sample := {
		"ts": int(Time.get_unix_time_from_system()),
		"time": "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
		"app": String(info.get("app", "unknown")),
		"title": String(info.get("title", "")),
		"shot": "",
	}

	if Config.screenshot_enabled:
		var rel := _capture_shot()
		if rel != "":
			sample["shot"] = rel

	Store.append_sample(sample)
	sample_taken.emit(sample)

func _capture_shot() -> String:
	var day := Store.today_str()
	var dir := "%s/%s" % [SHOT_DIR, day]
	DirAccess.make_dir_recursive_absolute(dir)
	var t := Time.get_time_dict_from_system()
	var rel := "%s/%02d%02d%02d.png" % [day, t.hour, t.minute, t.second]
	var virtual := "%s/%s" % [SHOT_DIR, rel]
	var real := ProjectSettings.globalize_path(virtual)
	if Platform.capture_screenshot(real):
		return rel
	return ""
