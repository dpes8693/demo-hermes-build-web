# 桌寵史萊姆 Slime Pet 🟢

一隻會在桌面上自主漫遊的 2D 史萊姆桌寵，並內建「工時彙整」功能：
它會在背景定時記錄你目前在用哪個程式／視窗，最後一鍵幫你整理出**今天做了什麼**，
方便每天回報那 8 小時花在哪裡。

> 用 [Godot Engine 4.3+](https://godotengine.org/) 開發，跨平台（Windows / macOS / Linux）。

---

## 功能

- **桌面寵物**：透明、無邊框、永遠置頂的小視窗，史萊姆會果凍般彈跳並在桌面四處漫遊。
  - 左鍵**拖曳**可以把牠搬到任何地方。
  - 左鍵**單擊**叫出選單。
- **背景追蹤**：每隔一段時間（預設 60 秒）記錄目前前景視窗的 **App 名稱 + 視窗標題**。
  - 可選開啟 **螢幕截圖 + 本機 OCR**：在本機用 Tesseract 把畫面文字抽出來，
    **只保留辨識出的文字**，截圖預設辨識完即刪、永遠不離開電腦。
    這能解決「光看 App 名稱不準」的問題（例如分辨 Chrome 是在查文件還是看影片）。
  - 取窗、截圖、OCR 都在**背景執行緒**進行，史萊姆動畫不會卡頓。
- **今日總結**：把當天的文字紀錄彙整後送 [Claude API](https://docs.claude.com/)，
  產生一份條列式、含估計時數的中文工作日報，可一鍵複製去貼到回報系統。
  - 沒設定 API key 時，會退回**離線規則式彙整**（各 App 時間佔比 + 時間軸），完全不連網。

### 隱私設計

平常只在本機累積**文字**（視窗標題，以及 OCR 辨識出的螢幕文字），隱私風險低、零 API 成本；
只有當你按下「今日總結」時，才把整理過的**文字**送出去交給模型理解與分類。
**螢幕截圖只在本機做 OCR，圖片永遠不離開你的電腦**（預設辨識完即刪）。

---

## 快速開始

1. 安裝 **Godot Engine 4.3 或更新版**（標準版即可，不需要 .NET/C# 版）。
2. 開啟 Godot → **Import** → 選擇本資料夾的 `project.godot`。
3. 按 **▶ 執行**（F5）。史萊姆會出現在螢幕右下角。
4. 點史萊姆 → **設定** → 填入你的 `ANTHROPIC_API_KEY`、選擇模型、調整取樣間隔。
   - 也可以改用環境變數：啟動前設定 `ANTHROPIC_API_KEY`，程式會自動帶入。
5. 工作一整天後，點史萊姆 → **今日總結** → **產生總結**。

### 打包成執行檔

Godot → **Project → Export**，加入對應平台的 Export Preset（Windows/macOS/Linux），
匯出即可得到獨立執行檔。

---

## 各作業系統的前置需求 / 權限

取得「目前前景視窗」沒有統一 API，本專案用系統工具達成：

| 系統 | 取窗方式 | 需要安裝 / 授權 |
|------|----------|------------------|
| **Windows** | PowerShell + user32.dll（自動產生輔助腳本）| 通常免額外設定 |
| **macOS** | `osascript`（System Events）| 系統設定 → 隱私權與安全性 → **輔助使用** 要授權給執行此程式的 App；若要截圖另需 **螢幕錄製** 權限 |
| **Linux (X11)** | `xdotool` | 需 `sudo apt install xdotool`（或對應套件）。**Wayland** 下取窗/截圖受限，建議用 X11 工作階段 |

截圖（選用）使用：Windows = System.Drawing；macOS = `screencapture`；
Linux = `scrot` / `gnome-screenshot` / `import`（ImageMagick）擇一。

### 本機 OCR：安裝 Tesseract（啟用「螢幕截圖 + OCR」才需要）

OCR 用 [Tesseract](https://github.com/tesseract-ocr/tesseract)，需在 PATH 上。語言包要另裝
（在「設定」的 OCR 語言填 `eng`、`chi_tra+eng` 等；繁中需 `chi_tra`、簡中 `chi_sim`）。

| 系統 | 安裝指令 |
|------|----------|
| **Windows** | 安裝 [UB-Mannheim 版](https://github.com/UB-Mannheim/tesseract/wiki)，安裝時勾選語言包，並把安裝路徑加進 PATH |
| **macOS** | `brew install tesseract tesseract-lang` |
| **Linux (Debian/Ubuntu)** | `sudo apt install tesseract-ocr tesseract-ocr-chi-tra tesseract-ocr-eng` |

未安裝 Tesseract 時：截圖會略過 OCR，程式自動退回「只用視窗標題」，不會出錯。
（「設定」視窗會顯示是否偵測到 Tesseract。）

---

## 資料存放位置

全部存在 Godot 的 `user://` 目錄（各平台不同，可在 Godot 中
`OS.get_user_data_dir()` 查看）：

- `settings.cfg` — 設定（含 API key，請自行注意保管）。
- `activity/YYYY-MM-DD.json` — 每日活動樣本（含 OCR 文字）。
- `screenshots/YYYY-MM-DD/HHMMSS.png` — 截圖（**僅在「保留截圖檔」開啟時**才會留下；
  預設 OCR 完即刪）。

---

## 使用的模型 / 成本

預設模型為 **`claude-opus-4-8`**（最強）。彙整一天的文字日報屬輕量任務，
若想降低成本，可在「設定」改成 `claude-sonnet-4-6` 或 `claude-haiku-4-5`。
API 呼叫走原生 HTTP（`POST /v1/messages`），程式碼在 `scripts/summarizer.gd`。

---

## 專案結構

```
slime-pet/
├── project.godot              # Godot 專案設定（透明置頂視窗 + autoloads）
├── icon.svg
├── scenes/
│   └── main.tscn              # 主場景
└── scripts/
    ├── main.gd                # 視窗設定、漫遊、拖曳/點擊、選單、開視窗
    ├── slime.gd               # 程式繪製的史萊姆 + 彈跳動畫
    ├── config.gd   (autoload) # 設定讀寫
    ├── store.gd    (autoload) # 活動紀錄 JSON 儲存
    ├── platform.gd (autoload) # 跨平台取前景視窗 + 截圖
    ├── tracker.gd  (autoload) # 定時取樣
    ├── summarizer.gd(autoload)# 彙整 + 呼叫 Claude API
    ├── summary_window.gd      # 「今日總結」視窗
    └── settings_window.gd     # 「設定」視窗
```

---

## 已知限制

- **Wayland**：透明置頂視窗、全域取窗與截圖支援有限，建議在 X11 下執行。
- 時間估算是用「取樣次數 × 間隔」推估，並非精準計時；間隔越短越準（也越吃資源）。
- macOS 首次執行需手動到系統設定授權輔助使用/螢幕錄製，否則取窗會回傳 `unknown`。
- 本專案在無 Godot 執行環境下撰寫，建議在本機用 Godot 4.3+ 開啟後實測微調。
