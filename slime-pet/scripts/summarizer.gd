extends Node
## 一日總結 (autoload: Summarizer)
## 把當天的活動樣本彙整成文字，送 Claude API (/v1/messages) 產生工作回報。
## 沒有 API key 時，退回純規則式的離線彙整。

signal summary_ready(date_str: String, text: String)
signal summary_failed(date_str: String, message: String)

var _http: HTTPRequest
var _pending_date: String = ""
var _busy := false

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func is_busy() -> bool:
	return _busy

## 入口：產生某天的總結
func summarize(date_str: String) -> void:
	if _busy:
		summary_failed.emit(date_str, "上一個總結還在產生中，請稍候。")
		return

	var samples := Store.load_day(date_str)
	if samples.is_empty():
		summary_failed.emit(date_str, "%s 沒有任何活動紀錄。" % date_str)
		return

	var report := _build_report(date_str, samples)

	if not Config.has_api_key():
		# 離線模式：直接回傳規則式彙整
		summary_ready.emit(date_str, "【離線彙整（未設定 API key）】\n\n" + report)
		return

	_pending_date = date_str
	_busy = true
	_request_claude(report)

# ---------------------------------------------------------------------------
# 彙整：把樣本整理成人類可讀、也適合餵給模型的文字
# ---------------------------------------------------------------------------
func _build_report(date_str: String, samples: Array) -> String:
	var interval := Config.capture_interval_sec
	var minutes_per := float(interval) / 60.0

	# 依 App 累加次數
	var by_app: Dictionary = {}
	for s in samples:
		var app := String(s.get("app", "unknown"))
		by_app[app] = int(by_app.get(app, 0)) + 1

	# 排序：次數多到少
	var apps := by_app.keys()
	apps.sort_custom(func(a, b): return by_app[a] > by_app[b])

	var lines: Array = []
	lines.append("日期：%s" % date_str)
	lines.append("取樣間隔：%d 秒，總樣本數：%d" % [interval, samples.size()])
	lines.append("估計總時長：約 %.1f 小時" % (samples.size() * minutes_per / 60.0))
	lines.append("")
	lines.append("=== 各應用程式時間分配（估算） ===")
	for app in apps:
		var cnt := int(by_app[app])
		var mins := cnt * minutes_per
		lines.append("- %s：約 %.0f 分鐘（%d 筆）" % [app, mins, cnt])

	lines.append("")
	lines.append("=== 時間軸（time | app | 視窗標題） ===")
	# 控制長度：最多列 600 筆
	var shown := samples
	if samples.size() > 600:
		shown = samples.slice(samples.size() - 600, samples.size())
		lines.append("(僅顯示最後 600 筆)")
	for s in shown:
		lines.append("%s | %s | %s" % [
			String(s.get("time", "")),
			String(s.get("app", "")),
			String(s.get("title", "")),
		])

	return "\n".join(lines)

# ---------------------------------------------------------------------------
# Claude API
# ---------------------------------------------------------------------------
func _request_claude(report: String) -> void:
	var url := Config.anthropic_base_url + "/v1/messages"
	var headers := PackedStringArray([
		"content-type: application/json",
		"x-api-key: " + Config.api_key,
		"anthropic-version: 2023-06-01",
	])

	var system_prompt := "你是一位協助上班族撰寫『每日工作回報』的助理。" \
		+ "使用者提供了一整天電腦前景視窗的取樣紀錄（App 名稱與視窗標題），" \
		+ "以及每個 App 的估計時間。請根據這些線索，推論使用者今天實際在做哪些『工作項目／專案』，" \
		+ "並彙整成一份精煉的中文日報。要求：\n" \
		+ "1) 先用一句話總結今天的重點。\n" \
		+ "2) 接著用條列分項列出主要工作（依花費時間排序），每項註明推估時數。\n" \
		+ "3) 把瀏覽器、通訊軟體、休息等歸入合理類別，不要逐筆照抄視窗標題。\n" \
		+ "4) 最後一行給出『合計：約 X 小時』，盡量貼近 %.0f 小時的工時。\n" \
		+ "5) 若資訊不足以判斷某段在做什麼，誠實標註為『待確認』，不要編造。"
	system_prompt = system_prompt % Config.work_hours

	var body := {
		"model": Config.model,
		"max_tokens": 4096,
		"system": system_prompt,
		"messages": [
			{
				"role": "user",
				"content": "這是我今天的電腦活動紀錄，請幫我整理成可以直接貼上回報系統的日報：\n\n" + report,
			},
		],
	}

	# 進階思考 / effort：Opus 4.6+ / Sonnet 4.6 / Fable 5 支援；Haiku 不支援。
	if _supports_thinking(Config.model):
		body["thinking"] = {"type": "adaptive"}
		body["output_config"] = {"effort": "medium"}

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		summary_failed.emit(_pending_date, "無法送出請求（HTTPRequest error %d）。請檢查網路。" % err)

func _supports_thinking(m: String) -> bool:
	return m.begins_with("claude-opus-4-6") \
		or m.begins_with("claude-opus-4-7") \
		or m.begins_with("claude-opus-4-8") \
		or m.begins_with("claude-sonnet-4-6") \
		or m.begins_with("claude-fable-5") \
		or m.begins_with("claude-mythos-5")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var date := _pending_date
	_pending_date = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		summary_failed.emit(date, "連線失敗（result=%d）。請確認網路與 base_url。" % result)
		return

	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		summary_failed.emit(date, "回應解析失敗 (HTTP %d)：%s" % [response_code, text.substr(0, 300)])
		return

	if response_code < 200 or response_code >= 300:
		var msg := "HTTP %d" % response_code
		if data.has("error") and typeof(data["error"]) == TYPE_DICTIONARY:
			msg += "：" + String(data["error"].get("message", ""))
		summary_failed.emit(date, msg)
		return

	# 安全分類可能回傳 stop_reason = refusal（HTTP 200）
	if String(data.get("stop_reason", "")) == "refusal":
		summary_failed.emit(date, "請求被模型安全機制拒絕（refusal）。")
		return

	var out := ""
	if data.has("content") and typeof(data["content"]) == TYPE_ARRAY:
		for block in data["content"]:
			if typeof(block) == TYPE_DICTIONARY and String(block.get("type", "")) == "text":
				out += String(block.get("text", ""))

	if out.strip_edges() == "":
		summary_failed.emit(date, "模型沒有回傳文字內容。")
		return

	summary_ready.emit(date, out)
