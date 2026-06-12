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

# 寫進每日報告檔的提示，讓外部總結工具知道你一天大約要回報幾小時
var work_hours: float = 8.0

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
	work_hours = float(cf.get_value("report", "work_hours", 8.0))
	if export_dir.strip_edges() == "":
		export_dir = _default_export_dir()

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("output", "export_dir", export_dir)
	cf.set_value("capture", "interval_sec", capture_interval_sec)
	cf.set_value("capture", "screenshot_enabled", screenshot_enabled)
	cf.set_value("capture", "ocr_lang", ocr_lang)
	cf.set_value("capture", "keep_screenshots", keep_screenshots)
	cf.set_value("capture", "screenshot_keep_days", screenshot_keep_days)
	cf.set_value("capture", "tracking_enabled", tracking_enabled)
	cf.set_value("report", "work_hours", work_hours)
	cf.save(CONFIG_PATH)
	settings_changed.emit()
