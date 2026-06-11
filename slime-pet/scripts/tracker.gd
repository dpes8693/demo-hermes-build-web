extends Node
## 背景追蹤器 (autoload: Tracker)
## 定時取樣：前景視窗（文字）＋（選用）螢幕截圖→本機 OCR→只留文字。
## 取樣的「重活」（呼叫子程序取窗、截圖、OCR）都丟到背景執行緒，避免卡住史萊姆動畫。

signal sample_taken(sample: Dictionary)
signal state_changed(running: bool)

const SHOT_DIR := "user://screenshots"
const TMP_SHOT := "user://bin/_ocr_tmp.png"

var _timer: Timer
var _busy := false           # 避免取樣重疊

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://bin")
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
		_timer.start()

func is_running() -> bool:
	return not _timer.is_stopped()

func start() -> void:
	Config.tracking_enabled = true
	_timer.start()
	_on_tick()
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
	if _busy:
		return
	_busy = true
	# 把取窗 / 截圖 / OCR 丟到背景執行緒，主執行緒不卡
	WorkerThreadPool.add_task(_collect_sample)

## 在背景執行緒執行
func _collect_sample() -> void:
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

	if Config.screenshot_enabled:
		var res := _capture_and_ocr()
		sample["ocr"] = res.get("ocr", "")
		sample["shot"] = res.get("shot", "")

	Store.append_sample(sample)
	# 回主執行緒發訊號 / 釋放 busy
	call_deferred("_after_collect", sample)

func _after_collect(sample: Dictionary) -> void:
	_busy = false
	sample_taken.emit(sample)

## 截圖→OCR；預設 OCR 完即刪截圖（keep_screenshots=false）
func _capture_and_ocr() -> Dictionary:
	var keep := Config.keep_screenshots
	var virtual := ""
	var rel := ""

	if keep:
		var day := Store.today_str()
		var dir := "%s/%s" % [SHOT_DIR, day]
		DirAccess.make_dir_recursive_absolute(dir)
		var t := Time.get_time_dict_from_system()
		rel = "%s/%02d%02d%02d.png" % [day, t.hour, t.minute, t.second]
		virtual = "%s/%s" % [SHOT_DIR, rel]
	else:
		virtual = TMP_SHOT

	var real := ProjectSettings.globalize_path(virtual)
	if not Platform.capture_screenshot(real):
		return {"ocr": "", "shot": ""}

	var ocr := ""
	if Platform.ocr_available():
		ocr = Platform.ocr_image(real, Config.ocr_lang)

	if not keep:
		# 辨識完立刻刪掉截圖
		DirAccess.remove_absolute(real)
		rel = ""

	return {"ocr": ocr, "shot": rel}
