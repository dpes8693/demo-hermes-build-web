class_name SettingsWindow
extends Window
## 「設定」視窗（純記錄器版本）。
## UI 版面定義在 scenes/settings_window.tscn，這裡只保留邏輯。

@onready var _export_dir: LineEdit = %ExportDir
@onready var _interval: SpinBox = %Interval
@onready var _work_hours: SpinBox = %WorkHours
@onready var _screenshot: CheckBox = %Screenshot
@onready var _ocr_lang: LineEdit = %OcrLang
@onready var _keep_shots: CheckBox = %KeepShots
@onready var _tracking: CheckBox = %Tracking
@onready var _status: Label = %Status
@onready var _ocr_status: Label = %OcrStatus
@onready var _access_status: Label = %AccessibilityStatus
@onready var _open_dir_btn: Button = %OpenDirBtn
@onready var _save_btn: Button = %SaveBtn
@onready var _close_btn: Button = %CloseBtn

func _ready() -> void:
	close_requested.connect(hide)
	about_to_popup.connect(_refresh_env_status)
	_open_dir_btn.pressed.connect(_open_export_dir)
	_save_btn.pressed.connect(_on_save)
	_close_btn.pressed.connect(hide)

	_ocr_status.text = "Tesseract 偵測：" \
		+ ("已安裝 ✓" if Platform.ocr_available() else "未偵測到 ✗（請先安裝 tesseract）")
	_ocr_status.add_theme_color_override("font_color",
		Color(0.5, 0.85, 0.6) if Platform.ocr_available() else Color(0.9, 0.6, 0.5))

	load_from_config()

func _refresh_env_status() -> void:
	if _access_status == null:
		return
	var info: Dictionary = Platform.get_active_window()
	if OS.get_name() == "macOS" and String(info.get("app", "unknown")) == "unknown":
		_access_status.text = "未取得『輔助使用』權限，無法記錄前景視窗：" \
			+ "請到 系統設定 → 隱私權與安全性 → 輔助使用 授權本 App"
		_access_status.add_theme_color_override("font_color", Color(0.9, 0.6, 0.5))
	else:
		_access_status.text = "前景視窗偵測正常 ✓"
		_access_status.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6))

func _open_export_dir() -> void:
	var p := _export_dir.text.strip_edges()
	if p == "":
		return
	DirAccess.make_dir_recursive_absolute(p)
	OS.shell_open(p)

func load_from_config() -> void:
	if _export_dir == null:
		return
	_export_dir.text = Config.export_dir
	_interval.value = Config.capture_interval_sec
	_work_hours.value = Config.work_hours
	_tracking.button_pressed = Config.tracking_enabled
	_screenshot.button_pressed = Config.screenshot_enabled
	_ocr_lang.text = Config.ocr_lang
	_keep_shots.button_pressed = Config.keep_screenshots
	_refresh_env_status()

func _on_save() -> void:
	Config.export_dir = _export_dir.text.strip_edges()
	Config.capture_interval_sec = int(_interval.value)
	Config.work_hours = float(_work_hours.value)
	Config.screenshot_enabled = _screenshot.button_pressed
	Config.ocr_lang = _ocr_lang.text.strip_edges()
	Config.keep_screenshots = _keep_shots.button_pressed
	Config.tracking_enabled = _tracking.button_pressed
	# Tracker 監聽 Config.settings_changed，存檔後會自行套用間隔與開關
	Config.save_settings()
	_status.text = "已儲存。"
