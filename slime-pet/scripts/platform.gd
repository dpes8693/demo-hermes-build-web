extends Node
## 跨平台原生互動 (autoload: Platform)
## - get_active_window()  取得目前前景視窗的 App 名稱與標題
## - capture_screenshot(real_path)  對整個螢幕截圖（選用）
##
## 由於各作業系統取得「前景視窗」沒有統一 API，這裡用 OS.execute 呼叫系統工具：
##   Windows : PowerShell + user32.dll
##   macOS   : osascript (System Events)  ── 需在「系統設定 > 隱私權 > 輔助使用」授權
##   Linux   : xdotool (X11)              ── 需先安裝 xdotool；Wayland 取窗有限制
##
## 截圖：
##   Windows : PowerShell + System.Drawing
##   macOS   : screencapture            ── 需「螢幕錄製」權限
##   Linux   : scrot / gnome-screenshot / import 擇一

const BIN_DIR := "user://bin"

var _os := ""
var _win_active_ps := ""
var _win_shot_ps := ""

func _ready() -> void:
	_os = OS.get_name()
	if _os == "Windows":
		_write_windows_helpers()
	elif _os == "macOS":
		_write_macos_helper()

# ---------------------------------------------------------------------------
# 前景視窗
# ---------------------------------------------------------------------------
func get_active_window() -> Dictionary:
	match _os:
		"Windows":
			return _windows_active()
		"macOS":
			return _macos_active()
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _linux_active()
		_:
			return {"app": "unknown", "title": ""}

func _windows_active() -> Dictionary:
	var raw := _run("powershell", PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _win_active_ps
	]))
	var lines := raw.split("\n", false)
	var app := lines[0].strip_edges() if lines.size() > 0 else ""
	var title := lines[1].strip_edges() if lines.size() > 1 else ""
	if app == "" and title == "":
		return {"app": "unknown", "title": ""}
	return {"app": app, "title": title}

# Godot 的 OS.execute 會吞掉引數中的雙引號，AppleScript 字串會被破壞，
# 所以腳本先寫成檔案再以路徑執行。
var _mac_active_scpt := ""

func _write_macos_helper() -> void:
	DirAccess.make_dir_recursive_absolute(BIN_DIR)
	var src := """tell application "System Events"
	set frontApp to first application process whose frontmost is true
	set appName to name of frontApp
	set winTitle to ""
	set winPos to ""
	try
		set frontWin to front window of frontApp
		set winTitle to name of frontWin
		set p to position of frontWin
		set winPos to ((item 1 of p) as text) & "," & ((item 2 of p) as text)
	end try
end tell
return appName & "\\n" & winTitle & "\\n" & winPos
"""
	var path := BIN_DIR + "/active.applescript"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(src)
		f.close()
		_mac_active_scpt = ProjectSettings.globalize_path(path)

func _macos_active() -> Dictionary:
	if _mac_active_scpt == "":
		return {"app": "unknown", "title": ""}
	var raw := _run("osascript", PackedStringArray([_mac_active_scpt]))
	var lines := raw.split("\n", false)
	var app := lines[0].strip_edges() if lines.size() > 0 else ""
	var title := lines[1].strip_edges() if lines.size() > 1 else ""
	if app == "":
		return {"app": "unknown", "title": ""}
	var result := {"app": app, "title": title}
	# 第三行是前景視窗左上角座標 "x,y"（全域螢幕座標），供挑選要截的螢幕
	if lines.size() > 2 and lines[2].contains(","):
		var xy := lines[2].strip_edges().split(",")
		if xy.size() == 2 and xy[0].is_valid_float() and xy[1].is_valid_float():
			result["win_pos"] = Vector2(xy[0].to_float(), xy[1].to_float())
	return result

func _linux_active() -> Dictionary:
	var title := _run("xdotool", PackedStringArray(["getactivewindow", "getwindowname"]))
	var cls := _run("xdotool", PackedStringArray(["getactivewindow", "getwindowclassname"]))
	cls = cls.strip_edges()
	title = title.strip_edges()
	if cls == "" and title == "":
		# xdotool 不存在或 Wayland 取不到
		return {"app": "unknown(需安裝 xdotool，且在 X11 下)", "title": ""}
	if cls == "":
		cls = "unknown"
	return {"app": cls, "title": title}

# ---------------------------------------------------------------------------
# 截圖（real_path 必須是真實檔案系統路徑，例如 globalize_path 之後）
# 一律輸出 JPEG 並縮到 MAX_SHOT_WIDTH 寬，控制硬碟用量；OCR 辨識率幾乎不受影響。
# 多螢幕：Windows / Linux 工具本來就截整個虛擬桌面（含所有螢幕）；
# macOS 的 screencapture 單檔只截主螢幕，因此用 screen_index 指定
# 「前景視窗所在的那面螢幕」（screencapture -D 的編號從 1 起算）。
# ---------------------------------------------------------------------------
const MAX_SHOT_WIDTH := 1920

func capture_screenshot(real_path: String, screen_index: int = -1) -> bool:
	match _os:
		"Windows":
			_run("powershell", PackedStringArray([
				"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _win_shot_ps,
				real_path, str(MAX_SHOT_WIDTH)
			]))
		"macOS":
			var args := PackedStringArray(["-x", "-t", "jpg"])
			if screen_index >= 0:
				args.append("-D")
				args.append(str(screen_index + 1))
			args.append(real_path)
			_run("screencapture", args)
			if FileAccess.file_exists(real_path):
				# Retina 截圖動輒數千px寬：縮到 MAX_SHOT_WIDTH，並壓 JPEG 品質
				# （normal ≈ 中等品質，對 OCR 足夠；不指定的話 sips 會用高品質回存反而變大）
				_run("sips", PackedStringArray([
					"-s", "format", "jpeg", "-s", "formatOptions", "normal",
					"--resampleHeightWidthMax", str(MAX_SHOT_WIDTH), real_path
				]))
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			if not _try_linux_shot(real_path):
				return false
			# 有 ImageMagick 就順手縮圖（沒有也不影響截圖本身）
			OS.execute("mogrify", PackedStringArray([
				"-resize", "%dx%d>" % [MAX_SHOT_WIDTH, MAX_SHOT_WIDTH], real_path
			]))
		_:
			return false
	return FileAccess.file_exists(real_path)

func _try_linux_shot(real_path: String) -> bool:
	# 依序嘗試常見工具
	if OS.execute("scrot", PackedStringArray(["-o", real_path])) == 0:
		return true
	if OS.execute("gnome-screenshot", PackedStringArray(["-f", real_path])) == 0:
		return true
	if OS.execute("import", PackedStringArray(["-window", "root", real_path])) == 0:
		return true
	return false

# ---------------------------------------------------------------------------
# 本機 OCR（Tesseract）── 圖片不離開電腦，只回傳辨識出的文字
# ---------------------------------------------------------------------------
var _ocr_checked := false
var _ocr_ok := false

## 系統是否裝了 tesseract（且在 PATH 上）。結果快取，避免每次取樣都開子程序。
func ocr_available() -> bool:
	if not _ocr_checked:
		var out: Array = []
		_ocr_ok = OS.execute("tesseract", PackedStringArray(["--version"]), out, true) == 0
		_ocr_checked = true
	return _ocr_ok

## 對圖檔做 OCR；lang 例如 "eng" 或 "chi_tra+eng"（需安裝對應語言包）
func ocr_image(real_path: String, lang: String) -> String:
	if lang.strip_edges() == "":
		lang = "eng"
	var out: Array = []
	# tesseract <影像> stdout -l <語言>  ── 結果輸出到 stdout
	# read_stderr=false：缺語言包等錯誤訊息不可混進辨識結果寫入紀錄
	var code := OS.execute("tesseract",
		PackedStringArray([real_path, "stdout", "-l", lang]), out, false)
	if code != 0 or out.is_empty():
		return ""
	return _clean_ocr(String(out[0]))

func _clean_ocr(text: String) -> String:
	# 去掉空白與雜訊行，壓成單行，並限制長度避免日報過長
	var kept: Array = []
	for ln in text.split("\n", false):
		var s := ln.strip_edges()
		if s.length() >= 2:
			kept.append(s)
	var joined := " / ".join(kept)
	if joined.length() > 600:
		joined = joined.substr(0, 600)
	return joined

# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _run(cmd: String, args: PackedStringArray) -> String:
	var out: Array = []
	var code := OS.execute(cmd, args, out, true)
	if code == -1:
		return ""
	if out.size() > 0:
		return String(out[0])
	return ""

func _write_windows_helpers() -> void:
	DirAccess.make_dir_recursive_absolute(BIN_DIR)

	var active_src := """Add-Type @\"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinFg {
  [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
  [DllImport(\"user32.dll\")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr h, out uint id);
}
\"@
$h = [WinFg]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder 1024
[void][WinFg]::GetWindowText($h, $sb, 1024)
$procId = [uint32]0
[void][WinFg]::GetWindowThreadProcessId($h, [ref]$procId)
$name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
Write-Output $name
Write-Output $sb.ToString()
"""
	_save_text("%s/win_active.ps1" % BIN_DIR, active_src)
	_win_active_ps = ProjectSettings.globalize_path("%s/win_active.ps1" % BIN_DIR)

	var shot_src := """Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$g.Dispose()
# 縮到最大寬度（$args[1]）並存成 JPEG，控制硬碟用量
$maxW = [int]$args[1]
if ($bmp.Width -gt $maxW) {
  $h = [int]($bmp.Height * $maxW / $bmp.Width)
  $small = New-Object System.Drawing.Bitmap $bmp, $maxW, $h
  $bmp.Dispose(); $bmp = $small
}
$bmp.Save($args[0], [System.Drawing.Imaging.ImageFormat]::Jpeg)
$bmp.Dispose()
"""
	_save_text("%s/win_shot.ps1" % BIN_DIR, shot_src)
	_win_shot_ps = ProjectSettings.globalize_path("%s/win_shot.ps1" % BIN_DIR)

func _save_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
