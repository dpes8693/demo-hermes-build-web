class_name SummaryWindow
extends Window
## 「今日彙整（本機預覽）」視窗。
## UI 版面定義在 scenes/summary_window.tscn，這裡只保留邏輯：
## 顯示 Store 產生的當日預彙整報告、複製內容、開啟輸出資料夾。

@onready var _date_picker: OptionButton = %DatePicker
@onready var _output: RichTextLabel = %Output
@onready var _status: Label = %Status
@onready var _reload_btn: Button = %ReloadBtn
@onready var _folder_btn: Button = %FolderBtn
@onready var _copy_btn: Button = %CopyBtn
@onready var _close_btn: Button = %CloseBtn

var _last_text := ""

func _ready() -> void:
	close_requested.connect(hide)
	_date_picker.item_selected.connect(func(_i): _refresh_output())
	_reload_btn.pressed.connect(_refresh_output)
	_folder_btn.pressed.connect(_open_folder)
	_copy_btn.pressed.connect(_on_copy)
	_close_btn.pressed.connect(hide)
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
