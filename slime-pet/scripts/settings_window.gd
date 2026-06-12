extends Window
## 「設定」視窗（純記錄器版本）。
## 不再有 API key / 模型設定；改為設定輸出資料夾、取樣間隔、OCR、工時等。

var _export_dir: LineEdit
var _interval: SpinBox
var _work_hours: SpinBox
var _screenshot: CheckBox
var _ocr_lang: LineEdit
var _keep_shots: CheckBox
var _tracking: CheckBox
var _status: Label

func _ready() -> void:
	title = "設定"
	size = Vector2i(560, 640)
	min_size = Vector2i(480, 560)
	exclusive = false
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# 輸出資料夾 + 開啟按鈕
	_export_dir = LineEdit.new()
	_export_dir.placeholder_text = "例如 /Users/you/Documents/SlimePet"
	var dir_row := HBoxContainer.new()
	dir_row.add_theme_constant_override("separation", 6)
	_export_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_row.add_child(_export_dir)
	var open_btn := Button.new()
	open_btn.text = "開啟"
	open_btn.pressed.connect(_open_export_dir)
	dir_row.add_child(open_btn)
	_add_field(vbox, "輸出資料夾（Claude 排程端指向這裡讀取）", dir_row)

	_interval = SpinBox.new()
	_interval.min_value = 5
	_interval.max_value = 3600
	_interval.step = 5
	_interval.suffix = " 秒"
	_add_field(vbox, "取樣間隔", _interval)

	_work_hours = SpinBox.new()
	_work_hours.min_value = 1
	_work_hours.max_value = 24
	_work_hours.step = 0.5
	_work_hours.suffix = " 小時"
	_add_field(vbox, "每日預計工時（寫進報告供總結參考）", _work_hours)

	_tracking = CheckBox.new()
	_tracking.text = "啟用背景追蹤（記錄前景視窗）"
	vbox.add_child(_tracking)

	_screenshot = CheckBox.new()
	_screenshot.text = "啟用螢幕截圖 + 本機 OCR（圖片不上傳，只留辨識文字）"
	vbox.add_child(_screenshot)

	_ocr_lang = LineEdit.new()
	_ocr_lang.placeholder_text = "例如 eng 或 chi_tra+eng"
	_add_field(vbox, "OCR 語言（Tesseract，需裝對應語言包）", _ocr_lang)

	_keep_shots = CheckBox.new()
	_keep_shots.text = "保留截圖檔（預設關閉；OCR 完即刪以省空間／保護隱私）"
	vbox.add_child(_keep_shots)

	var ocr_status := Label.new()
	ocr_status.text = "Tesseract 偵測：" \
		+ ("已安裝 ✓" if Platform.ocr_available() else "未偵測到 ✗（請先安裝 tesseract）")
	ocr_status.add_theme_color_override("font_color",
		Color(0.5, 0.85, 0.6) if Platform.ocr_available() else Color(0.9, 0.6, 0.5))
	vbox.add_child(ocr_status)

	var hint := Label.new()
	hint.text = "這個 App 只負責記錄：寫出 activity/*.json 與 reports/report-*.md。" \
		+ "總結交給 Claude 的本機排程任務去讀這個資料夾產生。截圖只在本機 OCR、永不上傳。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	var save_btn := Button.new()
	save_btn.text = "儲存"
	save_btn.pressed.connect(_on_save)
	bottom.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "關閉"
	close_btn.pressed.connect(hide)
	bottom.add_child(close_btn)

	load_from_config()

func _open_export_dir() -> void:
	var p := _export_dir.text.strip_edges()
	if p == "":
		return
	DirAccess.make_dir_recursive_absolute(p)
	OS.shell_open(p)

func _add_field(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)

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

func _on_save() -> void:
	Config.export_dir = _export_dir.text.strip_edges()
	Config.capture_interval_sec = int(_interval.value)
	Config.work_hours = float(_work_hours.value)
	Config.screenshot_enabled = _screenshot.button_pressed
	Config.ocr_lang = _ocr_lang.text.strip_edges()
	Config.keep_screenshots = _keep_shots.button_pressed
	Config.tracking_enabled = _tracking.button_pressed
	Config.save_settings()

	Tracker.apply_config()
	if Config.tracking_enabled and not Tracker.is_running():
		Tracker.start()
	elif not Config.tracking_enabled and Tracker.is_running():
		Tracker.stop()

	_status.text = "已儲存。"
