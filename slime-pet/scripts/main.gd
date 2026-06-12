extends Node2D
## 桌寵主控：設定透明置頂視窗、生成史萊姆、讓牠在桌面自主漫遊、
## 處理拖曳/點擊、彈出選單，以及開啟「今日總結」與「設定」視窗。

enum MenuId { SUMMARY, SETTINGS, TRACKING, WANDER, QUIT }

const SUMMARY_WINDOW_SCENE := preload("res://scenes/summary_window.tscn")
const SETTINGS_WINDOW_SCENE := preload("res://scenes/settings_window.tscn")

## 漫遊速度（px / 秒）
const WANDER_SPEED := 90.0
## 啟動後第一次漫遊前的等待秒數範圍
const INITIAL_IDLE_RANGE := Vector2(2.0, 5.0)
## 每次漫遊結束後的休息秒數範圍
const IDLE_RANGE := Vector2(3.0, 8.0)
## 超過這個距離（px）視為拖曳而非點擊
const CLICK_DRAG_THRESHOLD := 6.0
## 起始視窗位置：距離螢幕右下角的偏移（px）
const START_OFFSET := Vector2i(40, 80)
## 漫遊抵達目標的判定距離（px）
const ARRIVE_DISTANCE := 2.0
## 視窗基準邊長（px），實際邊長 = 此值 × Config.slime_scale
const BASE_WINDOW_SIZE := 240

var slime: Slime
var summary_win: SummaryWindow
var settings_win: SettingsWindow
var menu: PopupMenu

# 漫遊狀態（以浮點數保存視窗位置，再轉成整數設給 OS）
var _winpos := Vector2.ZERO
var _target := Vector2.ZERO
var _wandering := false
var _wander_enabled := true   # 自主移動總開關（選單可切換）
var _idle_timer := 2.0

# 拖曳/點擊
var _dragging := false
var _moved := false
var _press_pos := Vector2.ZERO

func _ready() -> void:
	_setup_window()

	slime = Slime.new()
	slime.position = Vector2(get_window().size) / 2.0   # 視窗中央
	add_child(slime)

	_build_menu()

	# 史萊姆大小隨設定即時生效（不需重啟）
	Config.settings_changed.connect(_apply_slime_scale)
	_apply_slime_scale()

	_winpos = Vector2(DisplayServer.window_get_position())
	_idle_timer = randf_range(INITIAL_IDLE_RANGE.x, INITIAL_IDLE_RANGE.y)
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
		rect.position.x + rect.size.x - size.x - START_OFFSET.x,
		rect.position.y + rect.size.y - size.y - START_OFFSET.y
	)
	DisplayServer.window_set_position(start)

## 依設定縮放史萊姆與 OS 視窗（保持視窗中心不動）
func _apply_slime_scale() -> void:
	var s := clampf(Config.slime_scale, 0.5, 2.0)
	var new_size := Vector2i(roundi(BASE_WINDOW_SIZE * s), roundi(BASE_WINDOW_SIZE * s))
	var old_size := DisplayServer.window_get_size()
	if new_size != old_size:
		var center := DisplayServer.window_get_position() + old_size / 2
		DisplayServer.window_set_size(new_size)
		DisplayServer.window_set_position(center - new_size / 2)
		_winpos = Vector2(DisplayServer.window_get_position())
	slime.scale = Vector2(s, s)
	slime.position = Vector2(new_size) / 2.0

func _usable_rect() -> Rect2i:
	var scr := DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_usable_rect(scr)

# ---------------------------------------------------------------------------
# 自主漫遊
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_ring()

	if _dragging:
		return

	# 自主移動關閉、互動中（選單／設定／彙整視窗開著）時暫停漫遊
	if not _wander_enabled or _ui_open():
		if _wandering:
			_stop_wandering()
		return

	if not _wandering:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_pick_target()
	else:
		_winpos = _winpos.move_toward(_target, WANDER_SPEED * delta)
		DisplayServer.window_set_position(Vector2i(_winpos.round()))
		slime.face_dir = signf(_target.x - _winpos.x)
		if _winpos.distance_to(_target) < ARRIVE_DISTANCE:
			_wandering = false
			slime.moving = false
			_idle_timer = randf_range(IDLE_RANGE.x, IDLE_RANGE.y)

## 把 Tracker 狀態餵給頭上的狀態環：
## 倒數中→進度環；取樣中（截圖/OCR）→loading；未追蹤→隱藏。
func _update_ring() -> void:
	if Tracker.is_busy():
		slime.ring_loading = true
	elif Tracker.is_running() and not Tracker.is_resting():
		slime.ring_loading = false
		slime.ring_progress = Tracker.sample_progress()
	else:
		slime.ring_loading = false
		slime.ring_progress = -1.0

func _ui_open() -> bool:
	if menu != null and menu.visible:
		return true
	if settings_win != null and is_instance_valid(settings_win) and settings_win.visible:
		return true
	if summary_win != null and is_instance_valid(summary_win) and summary_win.visible:
		return true
	return false

func _stop_wandering() -> void:
	_wandering = false
	slime.moving = false
	_idle_timer = randf_range(IDLE_RANGE.x, IDLE_RANGE.y)

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
			if _wandering:
				_stop_wandering()  # 點到史萊姆就先停下
		else:
			_dragging = false
			if not _moved:
				_open_menu()
	elif event is InputEventMouseMotion and _dragging:
		# 跨螢幕拖曳時 macOS 可能吃掉「放開」事件，_dragging 會卡住，
		# 之後滑鼠滑過就把視窗推走。改成每次移動都驗證左鍵真的還按著。
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			return
		if event.position.distance_to(_press_pos) > CLICK_DRAG_THRESHOLD:
			_moved = true
		var p := DisplayServer.window_get_position()
		DisplayServer.window_set_position(p + Vector2i(event.relative.round()))
		_winpos = Vector2(DisplayServer.window_get_position())

## 失焦也視為拖曳結束（放開事件遺失時的保險，否則 _dragging 卡住會連漫遊都停）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false

# ---------------------------------------------------------------------------
# 選單
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	menu = PopupMenu.new()
	add_child(menu)
	menu.add_item("今日彙整（本機）", MenuId.SUMMARY)
	menu.add_item("設定", MenuId.SETTINGS)
	menu.add_item("開始 / 暫停追蹤", MenuId.TRACKING)
	menu.add_item("自主移動", MenuId.WANDER)
	menu.add_separator()
	menu.add_item("離開", MenuId.QUIT)
	menu.id_pressed.connect(_on_menu_id)

func _open_menu() -> void:
	var checked := "（追蹤中）" if Tracker.is_running() else "（已暫停）"
	menu.set_item_text(menu.get_item_index(MenuId.TRACKING), "追蹤狀態 " + checked)
	var wander := "（開）" if _wander_enabled else "（關）"
	menu.set_item_text(menu.get_item_index(MenuId.WANDER), "自主移動 " + wander)
	menu.position = DisplayServer.mouse_get_position()
	menu.reset_size()
	menu.popup()

func _on_menu_id(id: int) -> void:
	match id:
		MenuId.SUMMARY:
			_show_summary()
		MenuId.SETTINGS:
			_show_settings()
		MenuId.TRACKING:
			Tracker.toggle()
		MenuId.QUIT:
			get_tree().quit()
		MenuId.WANDER:
			_wander_enabled = not _wander_enabled
			if not _wander_enabled and _wandering:
				_stop_wandering()

func _show_summary() -> void:
	if summary_win == null or not is_instance_valid(summary_win):
		summary_win = SUMMARY_WINDOW_SCENE.instantiate()
		add_child(summary_win)
	summary_win.refresh_dates()
	summary_win.popup_centered()

func _show_settings() -> void:
	if settings_win == null or not is_instance_valid(settings_win):
		settings_win = SETTINGS_WINDOW_SCENE.instantiate()
		add_child(settings_win)
	settings_win.load_from_config()
	settings_win.popup_centered()
