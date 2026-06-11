extends Node
## 活動紀錄儲存 (autoload: Store)
## 每天一個 JSON 檔：user://activity/YYYY-MM-DD.json
## 每筆樣本：{ "ts": 秒, "time": "HH:MM:SS", "app": "...", "title": "...", "shot": "相對路徑或空" }

const DIR := "user://activity"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

func today_str() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _path_for(date_str: String) -> String:
	return "%s/%s.json" % [DIR, date_str]

func load_day(date_str: String) -> Array:
	var path := _path_for(date_str)
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
	var date_str := today_str()
	var arr := load_day(date_str)
	arr.append(sample)
	var f := FileAccess.open(_path_for(date_str), FileAccess.WRITE)
	if f == null:
		push_warning("無法寫入活動紀錄: %s" % _path_for(date_str))
		return
	f.store_string(JSON.stringify(arr))
	f.close()

## 列出所有有紀錄的日期（新到舊）
func dates() -> Array:
	var result: Array = []
	var d := DirAccess.open(DIR)
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
