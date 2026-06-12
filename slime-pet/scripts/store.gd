extends Node
## 活動紀錄與每日彙整 (autoload: Store)
##
## 輸出到 Config.export_dir（友善的絕對路徑資料夾），結構：
##   <export_dir>/activity/YYYY-MM-DD.jsonl  ← 原始樣本（一行一筆 JSON，追加寫入）
##   <export_dir>/reports/report-YYYY-MM-DD.md ← 機械式預彙整（給外部總結工具讀）
##   <export_dir>/screenshots/...             ← 截圖（僅在 keep_screenshots 開啟時）
##
## 每筆樣本：{ "ts", "time":"HH:MM:SS", "app", "title", "ocr", "shot" }
##
## 路徑相關函式都接受可選的 base 參數：背景執行緒取樣時由 Tracker 在主執行緒
## 先快照一份傳進來，避免和「設定視窗改 export_dir」產生跨執行緒競爭。

func base_dir() -> String:
	var d := Config.export_dir.strip_edges()
	if d == "":
		d = ProjectSettings.globalize_path("user://SlimePet")
	return d

func activity_dir(base: String = "") -> String:
	return (base if base != "" else base_dir()).path_join("activity")

func reports_dir(base: String = "") -> String:
	return (base if base != "" else base_dir()).path_join("reports")

func screenshots_dir(base: String = "") -> String:
	return (base if base != "" else base_dir()).path_join("screenshots")

func today_str() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _activity_path(date_str: String, base: String = "") -> String:
	return activity_dir(base).path_join(date_str + ".jsonl")

func _legacy_activity_path(date_str: String, base: String = "") -> String:
	return activity_dir(base).path_join(date_str + ".json")

func _report_path(date_str: String, base: String = "") -> String:
	return reports_dir(base).path_join("report-" + date_str + ".md")

# ---------------------------------------------------------------------------
# 樣本讀寫（JSONL：一行一筆，append-only，當機最多丟最後一行）
# ---------------------------------------------------------------------------
func load_day(date_str: String, base: String = "") -> Array:
	var samples := _load_legacy_json(_legacy_activity_path(date_str, base))
	var path := _activity_path(date_str, base)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line == "":
					continue
				var parsed = JSON.parse_string(line)
				if typeof(parsed) == TYPE_DICTIONARY:
					samples.append(parsed)
			f.close()
	return samples

## 讀舊版「整檔 JSON 陣列」格式（升級前的既有紀錄）
func _load_legacy_json(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_ARRAY else []

func append_sample(sample: Dictionary, base: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(activity_dir(base))
	var path := _activity_path(today_str(), base)
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("無法寫入活動紀錄: %s" % path)
		return
	f.store_line(JSON.stringify(sample))
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
		if not d.current_is_dir():
			var date := ""
			if fname.ends_with(".jsonl"):
				date = fname.trim_suffix(".jsonl")
			elif fname.ends_with(".json"):
				date = fname.trim_suffix(".json")
			if date != "" and not result.has(date):
				result.append(date)
		fname = d.get_next()
	d.list_dir_end()
	result.sort()
	result.reverse()
	return result

# ---------------------------------------------------------------------------
# 截圖清理：刪除超過 keep_days 天的日期子資料夾（資料夾名即 YYYY-MM-DD）
# ---------------------------------------------------------------------------
func cleanup_screenshots(keep_days: int, base: String = "") -> void:
	if keep_days <= 0:
		return
	var dir_path := screenshots_dir(base)
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	# 用「今天 - keep_days」的日期字串比較；資料夾名是 ISO 日期，字典序即時間序
	var cutoff_ts := Time.get_unix_time_from_system() - keep_days * 86400
	var cutoff := Time.get_date_string_from_unix_time(int(cutoff_ts))
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if d.current_is_dir() and fname.match("????-??-??") and fname < cutoff:
			_remove_dir_recursive(dir_path.path_join(fname))
		fname = d.get_next()
	d.list_dir_end()

func _remove_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		var child := path.path_join(fname)
		if d.current_is_dir():
			_remove_dir_recursive(child)
		else:
			DirAccess.remove_absolute(child)
		fname = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)

# ---------------------------------------------------------------------------
# 每日預彙整報告（純機械式：時間佔比 + 時間軸 + OCR 摘錄）
# 由 Tracker 在每次取樣後呼叫 write_report() 更新，外部總結工具直接讀這份。
# ---------------------------------------------------------------------------
func write_report(date_str: String, base: String = "", interval: int = 0, work_hours: float = 0.0) -> void:
	DirAccess.make_dir_recursive_absolute(reports_dir(base))
	var text := build_report_text(date_str, base, interval, work_hours)
	var f := FileAccess.open(_report_path(date_str, base), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()

func build_report_text(date_str: String, base: String = "", interval: int = 0, work_hours: float = 0.0) -> String:
	var samples := load_day(date_str, base)
	if interval <= 0:
		interval = Config.capture_interval_sec
	if work_hours <= 0.0:
		work_hours = Config.work_hours
	var minutes_per := float(interval) / 60.0

	var lines: Array = []
	lines.append("# 電腦活動彙整 %s" % date_str)
	lines.append("")
	lines.append("> 這是桌寵自動產生的當日活動素材，供總結工具參考以撰寫工作日報。")
	lines.append("> 預計回報工時約 %.0f 小時；「螢幕文字摘錄」為本機 OCR 內容，可用來判斷實際在做什麼。" % work_hours)
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
