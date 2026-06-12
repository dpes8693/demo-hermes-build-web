extends Node
## 背景追蹤器 (autoload: Tracker)
## 定時取樣：前景視窗（文字）＋（選用）螢幕截圖→本機 OCR→只留文字。
## 取樣的「重活」（呼叫子程序取窗、截圖、OCR）都丟到背景執行緒，避免卡住史萊姆動畫。

signal sample_taken(sample: Dictionary)
signal state_changed(running: bool)

const TMP_SHOT := "user://bin/_ocr_tmp.png"

var _timer: Timer
var _busy := false           # 避免取樣重疊

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://bin")
	_timer = Timer.new()
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)
	Config.settings_changed.connect(_on_settings_changed)
	_apply_config()
	if Config.tracking_enabled:
		_start_timer()

## 設定變更的唯一入口：間隔生效、追蹤開關與 Config 對齊
func _on_settings_changed() -> void:
	_apply_config()
	if Config.tracking_enabled and not is_running():
		_start_timer()
	elif not Config.tracking_enabled and is_running():
		_stop_timer()

func _apply_config() -> void:
	_timer.wait_time = float(max(5, Config.capture_interval_sec))
	if not _timer.is_stopped():
		_timer.start()

func is_running() -> bool:
	return not _timer.is_stopped()

# start/stop/toggle 只改設定並落盤；計時器由 _on_settings_changed 統一同步，
# 所以選單切換和設定視窗儲存走同一條路，重啟後狀態也一致。
func start() -> void:
	_set_enabled(true)

func stop() -> void:
	_set_enabled(false)

func toggle() -> void:
	_set_enabled(not is_running())

func _set_enabled(on: bool) -> void:
	Config.tracking_enabled = on
	Config.save_settings()

func _start_timer() -> void:
	_timer.start()
	_on_tick()
	state_changed.emit(true)

func _stop_timer() -> void:
	_timer.stop()
	state_changed.emit(false)

func _on_tick() -> void:
	if _busy:
		return
	_busy = true
	# 在主執行緒快照本輪取樣需要的所有設定，背景執行緒不再讀共享狀態，
	# 避免和「設定視窗儲存」跨執行緒競爭。
	var snap := {
		"base": Store.base_dir(),
		"interval": Config.capture_interval_sec,
		"work_hours": Config.work_hours,
		"screenshot_enabled": Config.screenshot_enabled,
		"ocr_lang": Config.ocr_lang,
		"keep_screenshots": Config.keep_screenshots,
	}
	# 把取窗 / 截圖 / OCR 丟到背景執行緒，主執行緒不卡
	WorkerThreadPool.add_task(_collect_sample.bind(snap))

## 在背景執行緒執行；只使用 snap 中的設定
func _collect_sample(snap: Dictionary) -> void:
	var info := Platform.get_active_window()
	var t := Time.get_time_dict_from_system()
	var sample := {
		"ts": int(Time.get_unix_time_from_system()),
		"time": "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
		"app": String(info.get("app", "unknown")),
		"title": String(info.get("title", "")),
		"ocr": "",
		"shot": "",
	}

	if snap["screenshot_enabled"]:
		var res := _capture_and_ocr(snap)
		sample["ocr"] = res.get("ocr", "")
		sample["shot"] = res.get("shot", "")

	Store.append_sample(sample, snap["base"])
	# 更新每日預彙整報告供外部工具讀取
	Store.write_report(Store.today_str(), snap["base"], snap["interval"], snap["work_hours"])
	# 回主執行緒發訊號 / 釋放 busy
	call_deferred("_after_collect", sample)

func _after_collect(sample: Dictionary) -> void:
	_busy = false
	sample_taken.emit(sample)

## 截圖→OCR；預設 OCR 完即刪截圖（keep_screenshots=false）。背景執行緒執行。
func _capture_and_ocr(snap: Dictionary) -> Dictionary:
	var keep: bool = snap["keep_screenshots"]
	var rel := ""
	var real := ""
	if keep:
		var day := Store.today_str()
		var dir := Store.screenshots_dir(snap["base"]).path_join(day)
		DirAccess.make_dir_recursive_absolute(dir)
		var t := Time.get_time_dict_from_system()
		rel = "%s/%02d%02d%02d.png" % [day, t.hour, t.minute, t.second]
		real = dir.path_join("%02d%02d%02d.png" % [t.hour, t.minute, t.second])
	else:
		DirAccess.make_dir_recursive_absolute("user://bin")
		real = ProjectSettings.globalize_path(TMP_SHOT)

	if not Platform.capture_screenshot(real):
		return {"ocr": "", "shot": ""}

	var ocr := ""
	if Platform.ocr_available():
		ocr = Platform.ocr_image(real, snap["ocr_lang"])

	if not keep:
		# 辨識完立刻刪掉截圖
		DirAccess.remove_absolute(real)
		rel = ""

	return {"ocr": ocr, "shot": rel}
