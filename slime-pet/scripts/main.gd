extends Node2D
## 桌寵主控：設定透明置頂視窗、生成史萊姆、讓牠在桌面自主漫遊、
## 處理拖曳/點擊、彈出選單，以及開啟「今日總結」與「設定」視窗。

const SlimeScript := preload("res://scripts/slime.gd")
const SummaryWindow := preload("res://scripts/summary_window.gd")
const SettingsWindow := preload("res://scripts/settings_window.gd")

# 注意：以下三個刻意不加型別標註，因為要存取各自腳本特有的成員/方法
# （Godot 4 對「靜態型別變數存取未知成員」會編譯失敗）。
var slime
var summary_win
var settings_win
var menu: PopupMenu

# 漫遊狀態（以浮點數保存視窗位置，再轉成整數設給 OS）
var _winpos := Vector2.ZERO
var _target := Vector2.ZERO
var _wandering := false
var _idle_timer := 2.0
var _speed := 90.0           # px / 秒

# 拖曳/點擊
var _dragging := false
var _moved := false
var _press_pos := Vector2.ZERO

func _ready() -> void:
	_setup_window()

	slime = SlimeScript.new()
	slime.position = Vector2(120, 120)   # 視窗中央 (240x240)
	add_child(slime)

	_build_menu()

	_winpos = Vector2(DisplayServer.window_get_position())
	_idle_timer = randf_range(2.0, 5.0)
	set_process(true)

func _setup_window() -> void:
	var w := get_window()
	w.transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, w.get_window_id())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true, w.get_window_id())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true, w.get_window_id())
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))

	# 起始位置：螢幕右下角附近
	var rect := _usable_rect()
	var size := DisplayServer.window_get_size()
	var start := Vector2i(
		rect.position.x + rect.size.x - size.x - 40,
		rect.position.y + rect.size.y - size.y - 80
	)
	DisplayServer.window_set_position(start)

func _usable_rect() -> Rect2i:
	var scr := DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_usable_rect(scr)

# ---------------------------------------------------------------------------
# 自主漫遊
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _dragging:
		return

	if not _wandering:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_pick_target()
	else:
		_winpos = _winpos.move_toward(_target, _speed * delta)
		DisplayServer.window_set_position(Vector2i(_winpos.round()))
		slime.face_dir = signf(_target.x - _winpos.x)
		if _winpos.distance_to(_target) < 2.0:
			_wandering = false
			slime.moving = false
			_idle_timer = randf_range(3.0, 8.0)

func _pick_target() -> void:
	var rect := _usable_rect()
	var size := DisplayServer.window_get_size()
	var max_x := rect.position.x + rect.size.x - size.x
	var max_y := rect.position.y + rect.size.y - size.y
	_target = Vector2(
		randf_range(rect.position.x, max(rect.position.x, max_x)),
		randf_range(rect.position.y, max(rect.position.y, max_y))
	)
	_wandering = true
	slime.moving = true

# ---------------------------------------------------------------------------
# 滑鼠：左鍵拖曳搬動史萊姆；單擊（沒拖動）開選單
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_moved = false
			_press_pos = event.position
		else:
			_dragging = false
			if not _moved:
				_open_menu()
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 6.0:
			_moved = true
		var p := DisplayServer.window_get_position()
		DisplayServer.window_set_position(p + Vector2i(event.relative.round()))
		_winpos = Vector2(DisplayServer.window_get_position())

# ---------------------------------------------------------------------------
# 選單
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	menu = PopupMenu.new()
	add_child(menu)
	menu.add_item("今日彙整（本機）", 0)
	menu.add_item("設定", 1)
	menu.add_item("開始 / 暫停追蹤", 2)
	menu.add_separator()
	menu.add_item("離開", 3)
	menu.id_pressed.connect(_on_menu_id)

func _open_menu() -> void:
	var checked := "（追蹤中）" if Tracker.is_running() else "（已暫停）"
	menu.set_item_text(menu.get_item_index(2), "追蹤狀態 " + checked)
	menu.position = DisplayServer.mouse_get_position()
	menu.reset_size()
	menu.popup()

func _on_menu_id(id: int) -> void:
	match id:
		0:
			_show_summary()
		1:
			_show_settings()
		2:
			Tracker.toggle()
		3:
			get_tree().quit()

func _show_summary() -> void:
	if summary_win == null or not is_instance_valid(summary_win):
		summary_win = SummaryWindow.new()
		add_child(summary_win)
	summary_win.refresh_dates()
	summary_win.popup_centered()

func _show_settings() -> void:
	if settings_win == null or not is_instance_valid(settings_win):
		settings_win = SettingsWindow.new()
		add_child(settings_win)
	settings_win.load_from_config()
	settings_win.popup_centered()
