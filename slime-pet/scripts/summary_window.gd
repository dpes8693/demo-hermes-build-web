extends Window
## 「今日彙整（本機預覽）」視窗。
## 純記錄器版本：不呼叫任何 API，只顯示 Store 產生的當日預彙整報告，
## 方便你檢查素材，並可開啟輸出資料夾讓 Claude 排程端去讀。

var _date_picker: OptionButton
var _output: RichTextLabel
var _status: Label
var _last_text := ""

func _ready() -> void:
	title = "今日彙整（本機）"
	size = Vector2i(580, 660)
	min_size = Vector2i(440, 420)
	exclusive = false
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var label := Label.new()
	label.text = "日期："
	row.add_child(label)

	_date_picker = OptionButton.new()
	_date_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_picker.item_selected.connect(func(_i): _refresh_output())
	row.add_child(_date_picker)

	var reload_btn := Button.new()
	reload_btn.text = "重新整理"
	reload_btn.pressed.connect(_refresh_output)
	row.add_child(reload_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = false
	_output.selection_enabled = true
	_output.scroll_active = true
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_output)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	var folder_btn := Button.new()
	folder_btn.text = "開啟輸出資料夾"
	folder_btn.pressed.connect(_open_folder)
	bottom.add_child(folder_btn)

	var copy_btn := Button.new()
	copy_btn.text = "複製內容"
	copy_btn.pressed.connect(_on_copy)
	bottom.add_child(copy_btn)

	var close_btn := Button.new()
	close_btn.text = "關閉"
	close_btn.pressed.connect(hide)
	bottom.add_child(close_btn)

	refresh_dates()

func refresh_dates() -> void:
	if _date_picker == null:
		return
	_date_picker.clear()
	var today := Store.today_str()
	var dates := Store.dates()
	if not dates.has(today):
		dates.push_front(today)
	for d in dates:
		_date_picker.add_item(d + ("（今天）" if d == today else ""))
		_date_picker.set_item_metadata(_date_picker.item_count - 1, d)
	_refresh_output()

func _selected_date() -> String:
	if _date_picker.item_count == 0:
		return Store.today_str()
	return String(_date_picker.get_item_metadata(_date_picker.selected))

func _refresh_output() -> void:
	var d := _selected_date()
	_last_text = Store.build_report_text(d)
	_output.text = _last_text
	_status.text = "資料夾：%s" % Store.base_dir()

func _on_copy() -> void:
	DisplayServer.clipboard_set(_last_text)
	_status.text = "已複製到剪貼簿。"

func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(Store.base_dir())
	OS.shell_open(Store.base_dir())
