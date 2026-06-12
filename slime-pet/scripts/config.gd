extends Node
## 全域設定 (autoload: Config)
## 純記錄器版本：不再持有 API key / 模型設定。
## 設定存於 user://settings.cfg；活動紀錄輸出到使用者指定的「友善資料夾」export_dir。

const CONFIG_PATH := "user://settings.cfg"

# 輸出資料夾（絕對路徑）。預設放在「文件 / SlimePet」，方便 Claude 排程端的
# 檔案系統工具直接指向這裡讀取。底下會有 activity/ 與 reports/ 兩個子資料夾。
var export_dir: String = ""

var capture_interval_sec: int = 60          # 多久取樣一次（秒）
var screenshot_enabled: bool = false        # 是否啟用「螢幕截圖 + 本機 OCR」
var ocr_lang: String = "chi_tra+eng"        # Tesseract 辨識語言（需安裝對應語言包）
var keep_screenshots: bool = false          # OCR 後是否保留截圖檔（預設關閉、辨識完即刪）
var screenshot_keep_days: int = 14          # 截圖保留天數，超過自動清理（0 = 永久保留）
var tracking_enabled: bool = true           # 是否啟用背景追蹤

# 休息時段（時段內暫停取樣，避免掛機/下班忘了關追蹤被一直記錄）。
# 每行一條規則："HH:MM-HH:MM" 逗號分隔多段，跨夜可（起 > 迄）。
# 行首可寫星期幾（一二三四五六日，可多個）覆寫該日，整行取代預設：
#   12:00-13:00, 18:00-08:00     ← 預設（每天）
#   二 12:00-17:00               ← 週二只休下午（晚上要工作）
#   六日                          ← 週末整天取樣（只寫星期＝該日無休息時段）
var rest_periods: String = ""

# 寫進每日報告檔的提示，讓外部總結工具知道你一天大約要回報幾小時
var work_hours: float = 8.0

# 史萊姆大小倍率（0.5～2.0；視窗會跟著縮放，存檔即時生效）
var slime_scale: float = 1.0

signal settings_changed

func _ready() -> void:
	load_settings()

func _default_export_dir() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs != "":
		return docs.path_join("SlimePet")
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home != "":
		return home.path_join("SlimePet")
	return ProjectSettings.globalize_path("user://SlimePet")

func load_settings() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(CONFIG_PATH)
	if err != OK:
		export_dir = _default_export_dir()
		save_settings()
		return
	export_dir = String(cf.get_value("output", "export_dir", _default_export_dir()))
	capture_interval_sec = int(cf.get_value("capture", "interval_sec", 60))
	screenshot_enabled = bool(cf.get_value("capture", "screenshot_enabled", false))
	ocr_lang = String(cf.get_value("capture", "ocr_lang", "chi_tra+eng"))
	keep_screenshots = bool(cf.get_value("capture", "keep_screenshots", false))
	screenshot_keep_days = int(cf.get_value("capture", "screenshot_keep_days", 14))
	tracking_enabled = bool(cf.get_value("capture", "tracking_enabled", true))
	rest_periods = String(cf.get_value("capture", "rest_periods", ""))
	work_hours = float(cf.get_value("report", "work_hours", 8.0))
	slime_scale = clampf(float(cf.get_value("appearance", "slime_scale", 1.0)), 0.5, 2.0)
	if export_dir.strip_edges() == "":
		export_dir = _default_export_dir()
	_rest_cache = parse_rest_schedule(rest_periods)

# ---------------------------------------------------------------------------
# 休息時段解析 / 判斷
# ---------------------------------------------------------------------------

# 星期字 → Time.get_datetime_dict_from_system().weekday（0=週日）
const _DAY_CHARS := {"日": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6}

## 解析整份設定（多行）。回傳 Dictionary：
##   "default" → Array[[起,迄],…]（無星期前綴的行）
##   0..6      → 該星期的覆寫（整行取代預設；只寫星期＝該日無休息）
static func parse_rest_schedule(text: String) -> Dictionary:
	var sched: Dictionary = {}
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line == "":
			continue
		var days: Array = []
		var body := line
		# 行首第一個空白前若是純星期字（無數字），視為「指定星期」
		var sp := line.find(" ")
		var head := line.substr(0, sp) if sp > 0 else line
		if not _has_digit(head):
			for ch in head:
				if _DAY_CHARS.has(ch):
					days.append(_DAY_CHARS[ch])
			body = line.substr(sp + 1) if sp > 0 else ""
		var ranges := parse_rest_periods(body)
		if days.is_empty():
			sched["default"] = ranges
		else:
			for d in days:
				sched[d] = ranges
	return sched

static func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false

## 把 "12:00-13:00, 18:30-09:00" 解析成 [[起,迄], ...]（單位：當日第幾分鐘）。
## 跨夜（起 > 迄）保留原樣，由 is_in_rest 處理。無效片段直接略過。
static func parse_rest_periods(text: String) -> Array:
	var ranges: Array = []
	for seg in text.split(",", false):
		var pair := seg.strip_edges().split("-", false)
		if pair.size() != 2:
			continue
		var s := _parse_hhmm(pair[0])
		var e := _parse_hhmm(pair[1])
		if s < 0 or e < 0 or s == e:
			continue
		ranges.append([s, e])
	return ranges

static func _parse_hhmm(text: String) -> int:
	var p := text.strip_edges().split(":", false)
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return -1
	var h := int(p[0])
	var m := int(p[1])
	if h == 24 and m == 0:
		return 1440  # 允許 "24:00" 當作「當天結束」，這樣 00:00-24:00 = 全天休息
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m

# 解析結果快取（is_in_rest 會被 UI 每幀呼叫）；load/save 時更新
var _rest_cache: Dictionary = {}

## 目前（或指定的星期幾＋當日分鐘數）是否落在休息時段。
## 規則用「當下時間所在的那一天」查：該星期有覆寫就用覆寫，否則用預設。
func is_in_rest(now_minutes: int = -1, weekday: int = -1) -> bool:
	if now_minutes < 0 or weekday < 0:
		var dt := Time.get_datetime_dict_from_system()
		if now_minutes < 0:
			now_minutes = dt.hour * 60 + dt.minute
		if weekday < 0:
			weekday = dt.weekday
	var ranges: Array = _rest_cache.get(weekday, _rest_cache.get("default", []))
	for r in ranges:
		var s: int = r[0]
		var e: int = r[1]
		if s < e:
			if now_minutes >= s and now_minutes < e:
				return true
		else:
			# 跨夜：例如 18:30-09:00 → 晚上 18:30 後或早上 09:00 前
			if now_minutes >= s or now_minutes < e:
				return true
	return false

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("output", "export_dir", export_dir)
	cf.set_value("capture", "interval_sec", capture_interval_sec)
	cf.set_value("capture", "screenshot_enabled", screenshot_enabled)
	cf.set_value("capture", "ocr_lang", ocr_lang)
	cf.set_value("capture", "keep_screenshots", keep_screenshots)
	cf.set_value("capture", "screenshot_keep_days", screenshot_keep_days)
	cf.set_value("capture", "tracking_enabled", tracking_enabled)
	cf.set_value("capture", "rest_periods", rest_periods)
	cf.set_value("report", "work_hours", work_hours)
	cf.set_value("appearance", "slime_scale", slime_scale)
	cf.save(CONFIG_PATH)
	_rest_cache = parse_rest_schedule(rest_periods)
	settings_changed.emit()
