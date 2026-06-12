class_name Slime
extends Node2D
## 程式繪製的 2D 史萊姆（不需要美術素材）。
## 由 main.gd 加為子節點並放在視窗中央；main 負責移動 OS 視窗，
## slime 只負責「果凍彈跳」的擠壓/伸展動畫、眼睛與表情。

@export var base_radius_x: float = 78.0
@export var base_radius_y: float = 62.0
@export var body_color: Color = Color("5fd17a")
@export var body_color_light: Color = Color("8ff0a6")

# 色票
const COLOR_PUPIL := Color("1d2b22")
const COLOR_MOUTH_OPEN := Color("9c3b3b")

# 眨眼
const BLINK_DURATION := 0.18
const BLINK_INTERVAL_MIN := 2.0
const BLINK_INTERVAL_MAX := 5.0

# 彈跳
const HOP_SPEED_MOVING := 7.0
const HOP_SPEED_IDLE := 2.2
const SQUASH_AMP_MOVING := 0.16
const SQUASH_AMP_IDLE := 0.06
const HOP_HEIGHT_MOVING := 18.0
const HOP_HEIGHT_IDLE := 4.0

# 眼睛
const EYE_WIDTH := 11.0
const EYE_HEIGHT := 13.0

# 嘴巴
const SMILE_HALF_WIDTH := 16.0
const SMILE_HEIGHT := 8.0
const SMILE_LINE_WIDTH := 3.0

# 額頭上的取樣狀態環（畫在身體內，不會跳出視窗被裁切）
const RING_RADIUS := 10.0
const RING_WIDTH := 3.0
const RING_FOREHEAD_Y := 0.52               # 環中心高度 = body_center.y - ry * 此係數
const RING_TRACK_COLOR := Color(0, 0, 0, 0.18)
const RING_PROGRESS_COLOR := Color(1, 1, 1, 0.95)
const RING_LOADING_COLOR := Color("ffd166")
const RING_LOADING_SWEEP := TAU * 0.3       # loading 弧長
const RING_LOADING_SPEED := 5.0            # loading 旋轉速度（rad/s）

var moving := false          # 由 main 設定：是否正在橫越桌面
var face_dir := 1.0          # 1 向右、-1 向左

# 取樣狀態環（由 main 每幀餵入 Tracker 狀態）
var ring_progress := -1.0    # 0~1 = 倒數進度；< 0 = 隱藏（未追蹤）
var ring_loading := false    # true = 取樣中，畫旋轉 loading

var _t := 0.0                # 動畫時間
var _hop_phase := 0.0        # 彈跳相位
var _blink := 0.0            # 眨眼計時
var _blink_timer := 0.0

func _ready() -> void:
	_blink_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	# 移動時彈得快，閒置時慢慢呼吸
	var speed := HOP_SPEED_MOVING if moving else HOP_SPEED_IDLE
	_hop_phase += delta * speed

	# 眨眼
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink = BLINK_DURATION
		_blink_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
	if _blink > 0.0:
		_blink = max(0.0, _blink - delta)

	queue_redraw()

func _draw() -> void:
	# 彈跳：用 sin 控制擠壓量，移動時幅度較大
	var amp := SQUASH_AMP_MOVING if moving else SQUASH_AMP_IDLE
	var squash := sin(_hop_phase) * amp           # >0 變扁、<0 變高
	var rx := base_radius_x * (1.0 + squash * 0.6)
	var ry := base_radius_y * (1.0 - squash)
	var lift := -absf(sin(_hop_phase)) * (HOP_HEIGHT_MOVING if moving else HOP_HEIGHT_IDLE)  # 跳起時往上

	var body_center := Vector2(0, lift)

	# 影子（固定在地面，跳越高越小越淡）
	var shadow_scale := 1.0 - absf(sin(_hop_phase)) * 0.35
	_draw_ellipse(Vector2(0, base_radius_y * 0.55), rx * 0.85 * shadow_scale,
		ry * 0.28 * shadow_scale, Color(0, 0, 0, 0.18))

	# 身體
	_draw_ellipse(body_center, rx, ry, body_color)
	# 高光（偏左上的較亮橢圓）
	_draw_ellipse(body_center + Vector2(-rx * 0.22, -ry * 0.28),
		rx * 0.55, ry * 0.5, Color(body_color_light, 0.55))

	# 眼睛
	var eye_dx := rx * 0.34
	var eye_y := body_center.y - ry * 0.05
	var look := face_dir * rx * 0.06
	_draw_eye(Vector2(-eye_dx + look, eye_y))
	_draw_eye(Vector2(eye_dx + look, eye_y))

	# 嘴巴：移動時開心張嘴，閒置時微笑弧線
	_draw_mouth(body_center, rx, ry)

	# 額頭上的取樣狀態環（跟著果凍擠壓一起縮放位置）
	_draw_ring(Vector2(0, body_center.y - ry * RING_FOREHEAD_Y))

func _draw_ring(center: Vector2) -> void:
	if ring_loading:
		# 取樣中：旋轉的 loading 弧
		var start := _t * RING_LOADING_SPEED
		draw_arc(center, RING_RADIUS, start, start + RING_LOADING_SWEEP,
			24, RING_LOADING_COLOR, RING_WIDTH, true)
		return
	if ring_progress < 0.0:
		return  # 未追蹤：不顯示
	# 倒數進度：淡色軌道 + 從 12 點鐘方向順時針填滿
	draw_arc(center, RING_RADIUS, 0, TAU, 48, RING_TRACK_COLOR, RING_WIDTH, true)
	if ring_progress > 0.001:
		draw_arc(center, RING_RADIUS, -PI / 2, -PI / 2 + TAU * ring_progress,
			48, RING_PROGRESS_COLOR, RING_WIDTH, true)

func _draw_eye(center: Vector2) -> void:
	var open := 1.0 - clampf(_blink / BLINK_DURATION, 0.0, 1.0)  # 0=閉眼 1=睜眼
	var w := EYE_WIDTH
	var h := EYE_HEIGHT * open + 1.0
	_draw_ellipse(center, w, h, Color.WHITE)
	if open > 0.25:
		# 瞳孔朝向移動方向
		var pupil := center + Vector2(face_dir * 3.0, 2.0)
		_draw_ellipse(pupil, 5.0, 5.0 * open, COLOR_PUPIL)
		_draw_ellipse(pupil + Vector2(-1.6, -1.6), 1.6, 1.6, Color(1, 1, 1, 0.8))

func _draw_mouth(c: Vector2, rx: float, ry: float) -> void:
	var my := c.y + ry * 0.32
	if moving:
		# 張開的小嘴（橢圓）
		_draw_ellipse(Vector2(c.x, my), 12.0, 9.0, COLOR_MOUTH_OPEN)
	else:
		# 微笑弧線
		var pts := PackedVector2Array()
		var n := 14
		for i in range(n + 1):
			var tt := float(i) / float(n)
			var x := lerpf(-SMILE_HALF_WIDTH, SMILE_HALF_WIDTH, tt)
			var y := sin(tt * PI) * SMILE_HEIGHT
			pts.append(Vector2(c.x + x, my + y))
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], COLOR_PUPIL, SMILE_LINE_WIDTH, true)

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, segments: int = 64) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)
	# draw_colored_polygon 不做抗鋸齒，補一圈同色的抗鋸齒描邊把邊緣柔化
	pts.append(pts[0])
	draw_polyline(pts, color, 2.0, true)
