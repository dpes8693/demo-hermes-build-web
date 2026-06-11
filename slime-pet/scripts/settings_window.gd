extends Window
## 「設定」視窗（以程式碼建構 UI）。
## 可設定 API key、模型、取樣間隔、是否截圖、是否追蹤、預計工時。

var _api_key: LineEdit
var _model: OptionButton
var _base_url: LineEdit
var _interval: SpinBox
var _work_hours: SpinBox
var _screenshot: CheckBox
var _tracking: CheckBox
var _status: Label

func _ready() -> void:
	title = "設定"
	size = Vector2i(520, 520)
	min_size = Vector2i(420, 460)
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

	_api_key = LineEdit.new()
	_api_key.secret = true
	_api_key.placeholder_text = "sk-ant-..."
	_add_field(vbox, "Anthropic API Key", _api_key)

	_model = OptionButton.new()
	for m in Config.MODELS:
		_model.add_item(m)
	_add_field(vbox, "模型", _model)

	_base_url = LineEdit.new()
	_add_field(vbox, "API Base URL", _base_url)

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
	_add_field(vbox, "每日預計工時", _work_hours)

	_tracking = CheckBox.new()
	_tracking.text = "啟用背景追蹤（記錄前景視窗）"
	vbox.add_child(_tracking)

	_screenshot = CheckBox.new()
	_screenshot.text = "額外儲存本機螢幕截圖（僅存本機，不上傳）"
	vbox.add_child(_screenshot)

	var hint := Label.new()
	hint.text = "提示：總結時只會把『文字紀錄』送到 Claude API；截圖永遠留在本機。" \
		+ "API key 也可改用環境變數 ANTHROPIC_API_KEY。"
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
	if _api_key == null:
		return
	_api_key.text = Config.api_key
	_base_url.text = Config.anthropic_base_url
	_interval.value = Config.capture_interval_sec
	_work_hours.value = Config.work_hours
	_tracking.button_pressed = Config.tracking_enabled
	_screenshot.button_pressed = Config.screenshot_enabled
	var idx := Config.MODELS.find(Config.model)
	_model.selected = idx if idx >= 0 else 0

func _on_save() -> void:
	Config.api_key = _api_key.text.strip_edges()
	Config.model = _model.get_item_text(_model.selected)
	Config.anthropic_base_url = _base_url.text.strip_edges()
	Config.capture_interval_sec = int(_interval.value)
	Config.work_hours = float(_work_hours.value)
	Config.screenshot_enabled = _screenshot.button_pressed
	Config.tracking_enabled = _tracking.button_pressed
	Config.save_settings()

	Tracker.apply_config()
	if Config.tracking_enabled and not Tracker.is_running():
		Tracker.start()
	elif not Config.tracking_enabled and Tracker.is_running():
		Tracker.stop()

	_status.text = "已儲存。"
