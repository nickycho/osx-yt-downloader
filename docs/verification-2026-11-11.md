# macOS YouTube Downloader 驗證紀錄

日期：2026-11-11。目標為本機自用、Apple Silicon、macOS 14 以上。

## 產物與檢查

- `build/YouTubeDownloader.app`，版本 1.0 / build 1。
- `swift test`：9 項測試通過，涵蓋進度分段、未知檔案大小、直播／預定直播、已結束直播、音軌配對、DRM 排除、EJS 成功路徑警告、無效網址、重複載入、包含模板字元與換行的目的地路徑。
- `Scripts/package-app.sh`：Release 編譯成功、Info.plist 格式正確、執行檔存在。
- `vtool -show-build`：macOS 最低部署版本 14.0。

## 實際 App 操作

以公開影片 `https://www.youtube.com/watch?v=jNQXAC9IVRw` 做端到端檢查：

1. 從 `.app` 啟動並載入網址，顯示標題、頻道與 19 秒片長。
2. 內嵌播放器成功播放；可觀察到 Pause 控制與已播放時間前進。
3. 畫質選單列出來源提供的 240p 與 144p，選擇 144p。
4. 使用原生資料夾選擇器將測試輸出存到 `/tmp/osx-yt-downloader-smoke`。
5. UI 顯示下載完成與檔名；「在 Finder 中顯示」正確選取下載檔。
6. ffprobe 確認輸出含 192×144 影片與音軌、長度 19.028 秒，大小 437,575 bytes。
7. 同一畫質重複下載維持成功狀態，使用既有檔案。

此檢查只代表樣本在本次網路與已安裝工具環境可用；各影片的嵌入與格式權限仍由來源決定。

## 獨立審閱與修正

獨立靜態審閱指出的六項主要問題均已處理：

- 內嵌頁以 app bundle ID 提供來源識別，並將 IFrame API 錯誤傳回 native UI。
- 進度模板使用 `download:YT_PROGRESS|...`，解析實際輸出的 `YT_PROGRESS|` 標記。
- View model 入口與 UI 都限制單一操作，阻止 Return 重複啟動載入。
- 拒絕目前直播與預定直播；一般已結束直播可視格式使用。
- 成功與失敗的 stderr 都檢查缺少 EJS / JavaScript runtime 的診斷。
- 畫質清單只列出可配對音軌或影音合一格式的高度。

另外完成影片 ID 驗證、背景工具檢查（Deno 版本查詢有 5 秒上限），以及將目的地 `--paths` 與檔名模板分開。輸出路徑以帶標記的 JSON 字串取得，避免換行拆斷。沒有擱置的審閱事項。

依據：[YouTube WebView 嵌入識別](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity-and-credentials)、[YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference)、[yt-dlp 選項](https://github.com/yt-dlp/yt-dlp#verbosity-and-simulation-options)、[EJS 安裝指南](https://github.com/yt-dlp/yt-dlp/wiki/EJS)。

## 工程決策

- 原目錄沒有 Git repository，直接在指定目錄實作，沒有初始化 Git 或建立 worktree；代價是本次沒有 Git checkpoint。
- 預覽只要求 yt-dlp 與 Deno，缺少 ffmpeg/ffprobe 時仍可預覽，但停用下載並顯示安裝說明；代價是使用者可能先看到資訊再安裝下載工具。
- 進度 callback 使用 `@escaping` 以涵蓋背景程序輸出期間；callback 會保留至操作結束。
- Graph 未索引且 Serena 沒有 Swift language server，改用一般檔案編輯並以編譯、測試確認；代價是沒有符號編輯保護。
- 檔名加入所選解析度與影片 ID，避免其他畫質的既有檔案被當作此次結果；代價是檔名較長。
- 沒有 Git range 可審閱，因此獨立 reviewer 檢查完整新來源與打包腳本；審查範圍以本計畫的 app 檔案為準。
