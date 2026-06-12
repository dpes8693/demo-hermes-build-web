extends Node
## 活動紀錄與每日彙整 (autoload: Store)
##
## 輸出到 Config.export_dir（友善的絕對路徑資料夾），結構：
##   <export_dir>/activity/YYYY-MM-DD.json   ← 原始樣本
##   <export_dir>/reports/report-YYYY-MM-DD.md ← 機械式預彙整（給外部總結工具讀）
##   <export_dir>/screenshots/...             ← 截圖（僅在 keep_screenshots 開啟時）
##
## 每筆樣本：{ "ts", "time":"HH:MM:SS", "app", "title", "ocr", "shot" }

func base_dir() -> String:
	var d := Config.export_dir.strip_edges()
	if d == "":
		d = ProjectSettings.globalize_path("user://SlimePet")
	return d

func activity_dir() -> String:
	return base_dir().path_join("activity")

func reports_dir() -> String:
	return base_dir().path_join("reports")

func screenshots_dir() -> String:
	return base_dir().path_join("screenshots")

func today_str() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _activity_path(date_str: String) -> String:
	return activity_dir().path_join(date_str + ".json")

func _report_path(date_str: String) -> String:
	return reports_dir().path_join("report-" + date_str + ".md")

# ---------------------------------------------------------------------------
# 樣本讀寫
# ---------------------------------------------------------------------------
func load_day(date_str: String) -> Array:
	var path := _activity_path(date_str)
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []

func append_sample(sample: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(activity_dir())
	var date_str := today_str()
	var arr := load_day(date_str)
	arr.append(sample)
	var f := FileAccess.open(_activity_path(date_str), FileAccess.WRITE)
	if f == null:
		push_warning("無法寫入活動紀錄: %s" % _activity_path(date_str))
		return
	f.store_string(JSON.stringify(arr))
	f.close()

## 列出有紀錄的日期（新到舊）
func dates() -> Array:
	var result: Array = []
	var d := DirAccess.open(activity_dir())
	if d == null:
		return result
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".json"):
			result.append(fname.trim_suffix(".json"))
		fname = d.get_next()
	d.list_dir_end()
	result.sort()
	result.reverse()
	return result

# ---------------------------------------------------------------------------
# 每日預彙整報告（純機械式：時間佔比 + 時間軸 + OCR 摘錄）
# 由 Tracker 在每次取樣後呼叫 write_report() 更新，外部總結工具直接讀這份。
# ---------------------------------------------------------------------------
func write_report(date_str: String) -> void:
	DirAccess.make_dir_recursive_absolute(reports_dir())
	var text := build_report_text(date_str)
	var f := FileAccess.open(_report_path(date_str), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()

func build_report_text(date_str: String) -> String:
	var samples := load_day(date_str)
	var interval := Config.capture_interval_sec
	var minutes_per := float(interval) / 60.0

	var lines: Array = []
	lines.append("# 電腦活動彙整 %s" % date_str)
	lines.append("")
	lines.append("> 這是桌寵自動產生的當日活動素材，供總結工具參考以撰寫工作日報。")
	lines.append("> 預計回報工時約 %.0f 小時；「螢幕文字摘錄」為本機 OCR 內容，可用來判斷實際在做什麼。" % Config.work_hours)
	lines.append("")

	if samples.is_empty():
		lines.append("（今日尚無紀錄）")
		return "\n".join(lines)

	# 依 App 累加
	var by_app: Dictionary = {}
	for s in samples:
		var app := String(s.get("app", "unknown"))
		by_app[app] = int(by_app.get(app, 0)) + 1
	var apps := by_app.keys()
	apps.sort_custom(func(a, b): return by_app[a] > by_app[b])

	lines.append("- 取樣間隔：%d 秒；總樣本數：%d" % [interval, samples.size()])
	lines.append("- 估計總時長：約 %.1f 小時" % (samples.size() * minutes_per / 60.0))
	lines.append("")
	lines.append("## 各應用程式時間分配（估算）")
	for app in apps:
		var cnt := int(by_app[app])
		lines.append("- %s：約 %.0f 分鐘（%d 筆）" % [app, cnt * minutes_per, cnt])

	lines.append("")
	lines.append("## 時間軸（time | app | 視窗標題 | 螢幕文字摘錄）")
	var shown := samples
	if samples.size() > 600:
		shown = samples.slice(samples.size() - 600, samples.size())
		lines.append("(僅顯示最後 600 筆)")
	for s in shown:
		var ocr := String(s.get("ocr", "")).strip_edges()
		if ocr.length() > 160:
			ocr = ocr.substr(0, 160) + "…"
		lines.append("%s | %s | %s | %s" % [
			String(s.get("time", "")),
			String(s.get("app", "")),
			String(s.get("title", "")),
			ocr,
		])

	return "\n".join(lines)
