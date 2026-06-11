extends Node
## 全域設定 (autoload: Config)
## 設定存於 user://settings.cfg。API key 也可改用環境變數 ANTHROPIC_API_KEY。

const CONFIG_PATH := "user://settings.cfg"

# 可在「設定」視窗或這裡選擇的模型。預設為最強的 Opus 4.8；
# 若想省成本可改成 claude-sonnet-4-6 或 claude-haiku-4-5。
const MODELS := [
	"claude-opus-4-8",
	"claude-sonnet-4-6",
	"claude-haiku-4-5",
	"claude-fable-5",
]

var api_key: String = ""
var model: String = "claude-opus-4-8"
var anthropic_base_url: String = "https://api.anthropic.com"

var capture_interval_sec: int = 60          # 多久取樣一次（秒）
var screenshot_enabled: bool = false        # 是否啟用「螢幕截圖 + 本機 OCR」
var ocr_lang: String = "chi_tra+eng"        # Tesseract 辨識語言（需安裝對應語言包）
var keep_screenshots: bool = false          # OCR 後是否保留截圖檔（預設關閉、辨識完即刪）
var tracking_enabled: bool = true           # 是否啟用背景追蹤

# 一天預計回報的工時，用來輔助總結估算
var work_hours: float = 8.0

signal settings_changed

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(CONFIG_PATH)
	if err != OK:
		# 首次啟動：嘗試從環境變數帶入 API key，並寫出預設檔
		api_key = OS.get_environment("ANTHROPIC_API_KEY")
		save_settings()
		return
	api_key = String(cf.get_value("api", "key", OS.get_environment("ANTHROPIC_API_KEY")))
	model = String(cf.get_value("api", "model", "claude-opus-4-8"))
	anthropic_base_url = String(cf.get_value("api", "base_url", "https://api.anthropic.com"))
	capture_interval_sec = int(cf.get_value("capture", "interval_sec", 60))
	screenshot_enabled = bool(cf.get_value("capture", "screenshot_enabled", false))
	ocr_lang = String(cf.get_value("capture", "ocr_lang", "chi_tra+eng"))
	keep_screenshots = bool(cf.get_value("capture", "keep_screenshots", false))
	tracking_enabled = bool(cf.get_value("capture", "tracking_enabled", true))
	work_hours = float(cf.get_value("report", "work_hours", 8.0))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("api", "key", api_key)
	cf.set_value("api", "model", model)
	cf.set_value("api", "base_url", anthropic_base_url)
	cf.set_value("capture", "interval_sec", capture_interval_sec)
	cf.set_value("capture", "screenshot_enabled", screenshot_enabled)
	cf.set_value("capture", "ocr_lang", ocr_lang)
	cf.set_value("capture", "keep_screenshots", keep_screenshots)
	cf.set_value("capture", "tracking_enabled", tracking_enabled)
	cf.set_value("report", "work_hours", work_hours)
	cf.save(CONFIG_PATH)
	settings_changed.emit()

func has_api_key() -> bool:
	return api_key.strip_edges() != ""
