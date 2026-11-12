# YouTube Downloader for macOS

一個原生 macOS app：貼上 YouTube 影片網址後會自動載入預覽與可用畫質，選擇畫質與儲存資料夾，再下載影片。

## 功能

- 支援一般 `youtube.com` 單影片網址與 `youtu.be` 短網址。
- 使用 YouTube 隱私增強播放器預覽影片，顯示標題、頻道與片長。
- 依影片來源列出可用解析度，合併分離的影片與音訊串流。
- 顯示下載進度；下載完成後可在 Finder 中顯示檔案。
- 預設存到「下載項目」，也可以選擇其他資料夾。

## 系統需求

- macOS 14 或更新版本，Apple Silicon。
- Swift 6 與 Xcode Command Line Tools。
- `yt-dlp`、`ffmpeg`、`ffprobe` 與 Deno 2.3 或更新版本。
- 以 Python 套件安裝 yt-dlp 時，需在相同 Python 環境安裝 `yt-dlp-ejs`。

可用 Homebrew 安裝主要工具：

```sh
brew install yt-dlp ffmpeg deno
```

若 yt-dlp 顯示缺少 YouTube JavaScript 支援，請依照 yt-dlp 使用的 Python 環境安裝預設依賴：

```sh
python3 -m pip install -U "yt-dlp[default]"
```

`yt-dlp-ejs` 和 JavaScript runtime 的需求依 yt-dlp 安裝方式而異；請參考 [yt-dlp EJS 安裝指南](https://github.com/yt-dlp/yt-dlp/wiki/EJS) 與[依賴說明](https://github.com/yt-dlp/yt-dlp#dependencies)。官方 macOS standalone 執行檔已包含 EJS 元件，但仍需要支援的 JavaScript runtime。這個 app 不會自動安裝或更新任何工具。

## 建置與啟動

在專案目錄執行：

```sh
swift build
Scripts/package-app.sh
open build/YouTubeDownloader.app
```

產物位置：`build/YouTubeDownloader.app`。此版本供本機建置使用，未簽署與 notarize。

回歸檢查可使用 `swift test`；涵蓋貼上網址自動載入、MP4 輸出、進度解析、直播過濾、畫質音軌配對、依賴警告、網址驗證與重複提交。播放器以 app bundle ID 作為來源識別，依 [YouTube WebView 嵌入規格](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity-and-credentials) 載入。

## 使用方式

1. 貼上 YouTube 單一影片網址，App 會自動載入影片。
2. 等待影片預覽、資訊和可下載畫質顯示。
3. 選擇解析度與儲存資料夾，按「下載影片」。
4. 完成後按「在 Finder 中顯示」查看檔案。

解析度會依個別影片提供的串流而不同。若播放器禁止嵌入，仍可使用影片資訊與下載設定，或選擇在 YouTube 網頁播放。

## 限制

- 目前一次下載一部影片，不支援播放清單、直播、登入/cookie、私人或年齡限制影片，也不支援中斷後續傳。
- 只處理 yt-dlp 可直接存取的影片；不嘗試繞過存取限制。
- YouTube 的格式與存取方式可能變動；若解析失敗，請更新本機 yt-dlp。
