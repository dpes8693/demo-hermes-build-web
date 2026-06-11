extends Window
## 「今日總結」視窗（以程式碼建構 UI）。
## 選擇日期 -> 產生總結（呼叫 Summarizer）-> 顯示結果，可複製到剪貼簿。

var _date_picker: OptionButton
var _gen_btn: Button
var _copy_btn: Button
var _status: Label
var _output: RichTextLabel
var _last_text := ""

func _ready() -> void:
	title = "今日總結"
	size = Vector2i(560, 660)
	min_size = Vector2i(420, 420)
	exclusive = false
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# 第一列：日期 + 產生
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var label := Label.new()
	label.text = "日期："
	row.add_child(label)

	_date_picker = OptionButton.new()
	_date_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_date_picker)

	_gen_btn = Button.new()
	_gen_btn.text = "產生總結"
	_gen_btn.pressed.connect(_on_generate)
	row.add_child(_gen_btn)

	# 狀態列
	_status = Label.new()
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)

	# 結果
	_output = RichTextLabel.new()
	_output.bbcode_enabled = false
	_output.selection_enabled = true
	_output.scroll_active = true
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.text = "選擇日期後按「產生總結」。"
	vbox.add_child(_output)

	# 底部按鈕
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	_copy_btn = Button.new()
	_copy_btn.text = "複製到剪貼簿"
	_copy_btn.pressed.connect(_on_copy)
	bottom.add_child(_copy_btn)

	var close_btn := Button.new()
	close_btn.text = "關閉"
	close_btn.pressed.connect(hide)
	bottom.add_child(close_btn)

	Summarizer.summary_ready.connect(_on_summary_ready)
	Summarizer.summary_failed.connect(_on_summary_failed)

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
		var text := d + ("（今天）" if d == today else "")
		_date_picker.add_item(text)
		_date_picker.set_item_metadata(_date_picker.item_count - 1, d)

func _selected_date() -> String:
	if _date_picker.item_count == 0:
		return Store.today_str()
	return String(_date_picker.get_item_metadata(_date_picker.selected))

func _on_generate() -> void:
	var d := _selected_date()
	_status.text = "產生中…（呼叫模型可能需要數秒）"
	_gen_btn.disabled = true
	_output.text = ""
	Summarizer.summarize(d)

func _on_summary_ready(date_str: String, text: String) -> void:
	if date_str != _selected_date():
		return
	_gen_btn.disabled = false
	_status.text = "完成：%s" % date_str
	_last_text = text
	_output.text = text

func _on_summary_failed(date_str: String, message: String) -> void:
	_gen_btn.disabled = false
	_status.text = "失敗：%s" % message
	_output.text = ""

func _on_copy() -> void:
	if _last_text.strip_edges() == "":
		_status.text = "沒有可複製的內容。"
		return
	DisplayServer.clipboard_set(_last_text)
	_status.text = "已複製到剪貼簿。"
