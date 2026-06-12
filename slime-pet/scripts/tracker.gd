extends Node
## 背景追蹤器 (autoload: Tracker)
## 定時取樣：前景視窗（文字）＋（選用）螢幕截圖→本機 OCR→只留文字。
## 取樣的「重活」（呼叫子程序取窗、截圖、OCR）都丟到背景執行緒，避免卡住史萊姆動畫。

signal sample_taken(sample: Dictionary)
signal state_changed(running: bool)

const TMP_SHOT := "user://bin/_ocr_tmp.png"   # 原始解析度暫存圖，OCR 用
const SELF_APP_LABEL := "(桌寵自身)"  # 取樣到自己時記錄的 app 名稱

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

## 是否正在取樣（截圖/OCR 進行中）
func is_busy() -> bool:
	return _busy

## 距下次取樣的進度 0.0 → 1.0（供 UI 畫倒數環）
func sample_progress() -> float:
	if _timer.is_stopped() or _timer.wait_time <= 0.0:
		return 0.0
	return clampf(1.0 - _timer.time_left / _timer.wait_time, 0.0, 1.0)

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
	# 螢幕幾何也要在主執行緒先抄下來（DisplayServer 不保證執行緒安全）
	var screens: Array = []
	for i in range(DisplayServer.get_screen_count()):
		screens.append(Rect2(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))
	var snap := {
		"base": Store.base_dir(),
		"interval": Config.capture_interval_sec,
		"work_hours": Config.work_hours,
		"screenshot_enabled": Config.screenshot_enabled,
		"ocr_lang": Config.ocr_lang,
		"keep_screenshots": Config.keep_screenshots,
		"keep_days": Config.screenshot_keep_days,
		"screens": screens,
	}
	# 把取窗 / 截圖 / OCR 丟到背景執行緒，主執行緒不卡
	WorkerThreadPool.add_task(_collect_sample.bind(snap))

## 在背景執行緒執行；只使用 snap 中的設定
func _collect_sample(snap: Dictionary) -> void:
	var info := Platform.get_active_window()
	var app := String(info.get("app", "unknown"))
	var title := String(info.get("title", ""))
	# 前景視窗是史萊姆自己時仍寫入樣本（維持時間軸完整），
	# 但 app 改記為 SELF_APP_LABEL，避免報告把桌寵誤算成工作 App。
	if _is_self_window(app, title):
		app = SELF_APP_LABEL
	var t := Time.get_time_dict_from_system()
	var sample := {
		"ts": int(Time.get_unix_time_from_system()),
		"time": "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
		"app": app,
		"title": title,
		"ocr": "",
		"shot": "",
	}

	if snap["screenshot_enabled"]:
		# 多螢幕時截「前景視窗所在的螢幕」（只有 macOS 需要；其他平台截整個虛擬桌面）
		var screen_idx := -1
		if info.has("win_pos"):
			screen_idx = _screen_index_at(info["win_pos"], snap["screens"])
		var res := _capture_and_ocr(snap, screen_idx)
		sample["ocr"] = res.get("ocr", "")
		sample["shot"] = res.get("shot", "")

	Store.append_sample(sample, snap["base"])
	# 更新每日預彙整報告供外部工具讀取
	Store.write_report(Store.today_str(), snap["base"], snap["interval"], snap["work_hours"])
	# 回主執行緒發訊號 / 釋放 busy
	call_deferred("_after_collect", sample)

## 找出座標落在哪面螢幕（純函式）；找不到回 -1（沿用預設＝主螢幕）
func _screen_index_at(pos: Vector2, screens: Array) -> int:
	for i in range(screens.size()):
		if (screens[i] as Rect2).has_point(pos):
			return i
	return -1

## 判斷前景視窗是否為史萊姆本身（純函式，可在背景執行緒呼叫）
func _is_self_window(app: String, title: String) -> bool:
	if app == "Godot" or app == "godot":
		return true
	return title.contains("Slime Pet") or title.contains("桌寵史萊姆")

func _after_collect(sample: Dictionary) -> void:
	_busy = false
	sample_taken.emit(sample)

## 截圖→OCR→（保留時）壓縮存檔。背景執行緒執行。
## 順序刻意是「原圖先 OCR、再壓縮」：辨識吃滿解析度，儲存才縮圖省空間。
var _last_cleanup_date := ""

func _capture_and_ocr(snap: Dictionary, screen_idx: int = -1) -> Dictionary:
	# 1) 截原始解析度 PNG 到暫存
	DirAccess.make_dir_recursive_absolute("user://bin")
	var raw := ProjectSettings.globalize_path(TMP_SHOT)
	if not Platform.capture_screenshot(raw, screen_idx):
		return {"ocr": "", "shot": ""}

	# 2) 對原圖 OCR
	var ocr := ""
	if Platform.ocr_available():
		ocr = Platform.ocr_image(raw, snap["ocr_lang"])

	# 3) 要保留才壓縮成 JPEG 存進輸出資料夾；原圖一律刪
	var rel := ""
	if snap["keep_screenshots"]:
		var day := Store.today_str()
		var dir := Store.screenshots_dir(snap["base"]).path_join(day)
		DirAccess.make_dir_recursive_absolute(dir)
		var t := Time.get_time_dict_from_system()
		var fname := "%02d%02d%02d.jpg" % [t.hour, t.minute, t.second]
		Platform.compress_image(raw, dir.path_join(fname))  # 壓縮失敗時內部會複製原檔
		rel = "%s/%s" % [day, fname]
		# 每天第一次截圖時清掉過期的舊截圖
		if _last_cleanup_date != day:
			_last_cleanup_date = day
			Store.cleanup_screenshots(snap["keep_days"], snap["base"])
	DirAccess.remove_absolute(raw)

	return {"ocr": ocr, "shot": rel}
