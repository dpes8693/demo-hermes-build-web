# 桌寵史萊姆 Slime Pet 🟢

一隻會在桌面上自主漫遊的 2D 史萊姆桌寵,同時是個**輕量活動記錄器**:
它在背景定時記錄你目前在用哪個程式／視窗(可選螢幕截圖→本機 OCR),
並把當天素材整理成檔案。

> **設計理念:解耦。** 史萊姆**只負責記錄、寫檔**,不持有 API key、不發網路請求。
> 「總結成工作日報」交給 [Claude 的本機排程任務](https://code.claude.com/docs/en/desktop-scheduled-tasks)
> 去讀輸出資料夾自動產生。兩端各自獨立、互不耦合。

用 [Godot Engine 4.3+](https://godotengine.org/) 開發,跨平台(Windows / macOS / Linux)。

---

## 功能

- **桌面寵物**:透明、無邊框、永遠置頂的小視窗,史萊姆會果凍般彈跳並在桌面四處漫遊。
  - 左鍵**拖曳**搬動;左鍵**單擊**叫出選單。
- **背景記錄**:每隔一段時間(預設 60 秒)記錄前景視窗的 **App 名稱 + 視窗標題**。
  - 可選 **螢幕截圖 + 本機 OCR**:用 Tesseract 在本機抽出畫面文字,**只留文字**、
    截圖預設辨識完即刪(解決光看 App 名稱分不出在做什麼的問題)。
  - 取窗／截圖／OCR 都在**背景執行緒**進行,史萊姆動畫不卡頓。
- **每日預彙整**:每次取樣後自動更新 `report-YYYY-MM-DD.md`(各 App 時間佔比 + 時間軸 + OCR 摘錄),
  供外部總結工具直接讀,省去解析原始 JSON、也省 token。
- **本機預覽**:選單的「今日彙整(本機)」可檢視上述報告、複製、或一鍵開啟輸出資料夾。
  **完全不連網。**

---

## 輸出檔案(給外部總結工具讀取)

全部寫在你在「設定」指定的 `輸出資料夾`(預設 `文件/SlimePet`,絕對路徑,
方便 Claude 的檔案系統工具指向):

```
<輸出資料夾>/
├── activity/YYYY-MM-DD.jsonl     # 原始樣本，一行一筆 JSON（ts/time/app/title/ocr/shot）
├── reports/report-YYYY-MM-DD.md  # 機械式預彙整（建議外部工具讀這份）
└── screenshots/...               # 截圖（僅在「保留截圖檔」開啟時）
```

### 接到 Claude 排程端時的注意事項

- 因為素材是**本機檔案**,要用 **本機排程任務(Local Scheduled Task)**+ 檔案系統存取去讀,
  指向上面的輸出資料夾。**雲端例程(Remote Routine)在 Anthropic 雲端執行,讀不到你的本機檔案。**
- 本機任務**只在 Claude 應用開著、電腦醒著時才會觸發**,請確保你設定的下班總結時間點電腦是開的。

---

## 快速開始

1. 安裝 **Godot Engine 4.3+**(標準版即可,本專案在 4.6 開發)。
2. `git clone` 本 repo,Godot → **Import** → 選 `slime-pet/project.godot` → 按 **▶**(F5)。
3. (選用)裝齊下方「各平台依賴」,才能用截圖 + OCR;只看視窗標題的話不裝也能跑。
4. 點史萊姆 → **設定** → 確認/修改「輸出資料夾」、調整取樣間隔。
5. 讓它在背景跑;隨時可在「今日彙整(本機)」預覽,或開資料夾把檔案交給 Claude 排程任務。

> **要分享給同事測試?** 直接給原始碼(git clone)比打包成執行檔簡單:
> 打包不會把下方那些系統工具一起包進去,同事一樣得自己裝;而原始碼模式只要
> 「裝 Godot → 開 project.godot → 按 ▶」三步,還能看 log、改程式。
> 打包成 `.app`/`.exe` 只在「要給不裝 Godot 的一般使用者」時才值得。

### 一次裝齊依賴(複製貼上)

```bash
# macOS (Homebrew)
brew install --cask godot
brew install tesseract tesseract-lang        # OCR(選用)
# screencapture / sips / osascript 為系統內建,無需安裝

# Linux (Debian/Ubuntu)
sudo apt install xdotool scrot imagemagick \
     tesseract-ocr tesseract-ocr-chi-tra tesseract-ocr-eng
# Godot 由官網下載或 sudo snap install godot4

# Windows
#   Godot:    官網下載免安裝版
#   截圖/取窗: PowerShell 內建,免裝
#   OCR(選用):裝 UB-Mannheim 版 tesseract 並加進 PATH
```

### 打包成執行檔(進階,通常不需要)

先在 Godot `Editor → Manage Export Templates` 下載對應版本模板,
再 `Project → Export` 加入平台 preset 匯出。注意:**打包不含上述系統工具**,
目標機器仍需自行安裝它們、並在 macOS 授權「輔助使用 / 螢幕錄製」。

---

## 各作業系統的前置需求 / 權限

取得「目前前景視窗」沒有統一 API,本專案用系統工具達成:

| 系統 | 取窗方式 | 需要安裝 / 授權 |
|------|----------|------------------|
| **Windows** | PowerShell + user32.dll(自動產生輔助腳本)| 通常免額外設定 |
| **macOS** | `osascript`(System Events)| 系統設定 → 隱私權 → **輔助使用** 要授權;截圖另需 **螢幕錄製** 權限 |
| **Linux (X11)** | `xdotool` | `sudo apt install xdotool`。**Wayland** 取窗/截圖受限,建議用 X11 |

截圖(選用):Windows = System.Drawing;macOS = `screencapture` + `sips`(縮圖);
Linux = `scrot` / `gnome-screenshot` / `import` 擇一,壓縮另需 `convert`(ImageMagick)。
多螢幕:Windows/Linux 截整個虛擬桌面;macOS 截「前景視窗所在的那面螢幕」。

### 本機 OCR:安裝 Tesseract(啟用「螢幕截圖 + OCR」才需要)

需把 [Tesseract](https://github.com/tesseract-ocr/tesseract) 裝到 PATH,並另裝語言包
(在「設定」的 OCR 語言填 `eng`、`chi_tra+eng` 等;繁中需 `chi_tra`)。

| 系統 | 安裝 |
|------|------|
| **Windows** | [UB-Mannheim 版](https://github.com/UB-Mannheim/tesseract/wiki),安裝時勾語言包並加進 PATH |
| **macOS** | `brew install tesseract tesseract-lang` |
| **Linux** | `sudo apt install tesseract-ocr tesseract-ocr-chi-tra tesseract-ocr-eng` |

未安裝時:截圖會略過 OCR,自動退回「只用視窗標題」,不會出錯;設定視窗會顯示是否偵測到。

---

## 隱私

- 平常**完全離線**:只在本機累積文字(視窗標題、OCR 文字)與每日報告檔。
- **螢幕截圖只在本機做 OCR,圖片永遠不離開電腦**(預設辨識完即刪)。
- 這個 App **不含 API key、不發任何網路請求**;素材要不要送出、送到哪,完全由你那端的
  Claude 排程任務決定。

---

## 專案結構

```
slime-pet/
├── project.godot
├── icon.svg
├── scenes/main.tscn
└── scripts/
    ├── main.gd                # 視窗設定、漫遊、拖曳/點擊、選單
    ├── slime.gd               # 程式繪製的史萊姆 + 彈跳動畫
    ├── config.gd   (autoload) # 設定（輸出資料夾、間隔、OCR…）
    ├── store.gd    (autoload) # 寫 activity JSON + 每日 report.md（含彙整邏輯）
    ├── platform.gd (autoload) # 跨平台取前景視窗 / 截圖 / Tesseract OCR
    ├── tracker.gd  (autoload) # 背景執行緒定時取樣
    ├── summary_window.gd      # 「今日彙整（本機）」預覽視窗
    └── settings_window.gd     # 「設定」視窗
```

---

## 已知限制

- **Wayland**:透明置頂、全域取窗與截圖支援有限,建議在 X11 下執行。
- 時間估算是用「取樣次數 × 間隔」推估,非精準計時;間隔越短越準(也越吃資源)。
- macOS 首次需手動授權輔助使用/螢幕錄製,否則取窗會回傳 `unknown`。
- 本專案在無 Godot 執行環境下撰寫,建議在本機用 Godot 4.3+ 開啟後實測微調。
