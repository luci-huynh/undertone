# Local Translator

Ứng dụng thanh menu cho macOS: bôi đen chữ ở bất kỳ app nào → bấm **⌥T** (hoặc biểu tượng dịch cạnh con trỏ) → đọc bản dịch hiện dần trong popup. Dịch **hoàn toàn trên máy** qua [Ollama](https://ollama.com); chữ không rời khỏi máy.

Phiên bản: **0.1.0 (build 1)** — release candidate cho dùng cá nhân (xem `docs/RELEASE.md`).

## Yêu cầu

- macOS 14 trở lên (đã kiểm tra trên macOS 27.0, Apple M5, 24 GB).
- Ollama chạy trên máy tại `http://127.0.0.1:11434`.
- Model `translategemma:12b` (8,1 GB; khi đang dùng chiếm khoảng 8–9 GB RAM).
- Để build: Xcode 27 trở lên và một Apple ID (Personal Team là đủ).

## Cài đặt

1. **Ollama và model**
   ```sh
   ollama pull translategemma:12b
   ```
   App không tự tải model.
2. **Build và cài app**
   ```sh
   xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Release \
     -destination "generic/platform=macOS" -archivePath .build/LocalTranslator.xcarchive archive
   ditto .build/LocalTranslator.xcarchive/Products/Applications/LocalTranslator.app /Applications/LocalTranslator.app
   open /Applications/LocalTranslator.app
   ```
   Trên máy khác hoặc với Apple ID khác: mở project trong Xcode → target LocalTranslator → Signing & Capabilities → chọn Team của bạn (đổi bundle ID nếu Xcode báo trùng). Chi tiết: `docs/RELEASE.md`.
3. **Quyền Accessibility** (bắt buộc, để đọc chữ đã chọn): menu Local Translator → Settings… → Accessibility → cấp quyền, hoặc System Settings → Privacy & Security → Accessibility → bật Local Translator. Không cần quyền nào khác.
4. **Tuỳ chọn**: Settings → Khởi động → *Mở cùng macOS (Launch at Login)*.

## Sử dụng

| Thao tác | Kết quả |
|---|---|
| Bôi đen chữ → **⌥T** | Popup cạnh vùng chọn, bản dịch hiện dần |
| Kéo chuột hoặc nhấp đúp để bôi đen → bấm **biểu tượng dịch** cạnh con trỏ | Như ⌥T (tắt được trong Settings → Nút dịch khi bôi đen) |
| Chiều dịch | Tự nhận diện: English → Vietnamese, Vietnamese → English, ngôn ngữ khác → Vietnamese. Chữ quá ngắn/mơ hồ: đoán, tiêu đề ghi “(guessed)” |
| **⇄** | Dịch lại theo chiều ngược, chỉ cho lần này |
| **↻** / **Retry** | Dịch lại cùng đoạn (sau khi xong / khi lỗi) |
| **Copy** | Chép bản dịch đã xong |
| Kéo chỗ trống của popup | Di chuyển popup; nó giữ chỗ mới đến khi đóng |
| **Esc** hoặc × | Đóng, huỷ lượt đang dịch |

Menu thanh menu: trạng thái Ollama và model, Settings…, Open Ollama, Quit.

## Riêng tư

Chữ đã chọn chỉ gửi tới Ollama trên máy (`127.0.0.1`); không cloud, không analytics, không lịch sử dịch; log chỉ có số liệu (số ký tự, mili-giây). Chi tiết và bằng chứng: `docs/PRIVACY.md`.

## Khắc phục sự cố

| Thông báo / hiện tượng | Cách xử lý |
|---|---|
| “Local Translator needs Accessibility permission…” | Bấm *Open System Settings* và bật quyền. Sau khi build lại hoặc chuyển app sang máy khác có thể phải cấp lại |
| “Ollama is not running.” | Mở Ollama (menu → Open Ollama) rồi bấm *Retry* |
| “Translation model is not installed.” | `ollama pull translategemma:12b`, hoặc chọn model khác trong Settings |
| “The model took too long to start.” / “Ollama stopped responding.” | Thường do thiếu RAM hoặc Ollama bận; đợi rồi *Retry* |
| “Selected text is too long to translate at once.” | Giới hạn khoảng 5.000 ký tự tiếng Anh (ít hơn với tiếng Việt); chọn đoạn ngắn hơn |
| “Can't read selected text in this app.” | App đó không cho đọc chữ qua Accessibility (ví dụ Safari hiện tại) |
| Chrome, Brave, Slack, Notion không đọc được ở lần đầu | Lần đầu sau khi mở các app này cần khoảng 10–30 giây để bật chế độ trợ năng; thử lại sau đó |
| ⌥T không phản ứng | Settings → Phím tắt: nếu báo trùng, đóng app đang dùng ⌥T rồi *Thử lại*. Chỉ chạy một bản Local Translator cùng lúc |
| Lần dịch đầu tiên chậm (3–6 giây) | Ollama đang nạp model; các lần sau nhanh (model được giữ 30 phút) |

## Giới hạn đã biết

- Safari chưa đọc được chữ đã chọn.
- Chromium/Electron (Chrome, Brave, Slack, Notion) cần khởi động trợ năng ở lần đầu; popup có thể hiện ở con trỏ thay vì cạnh vùng chọn.
- Không OCR: PDF scan không có lớp chữ, ảnh và video không dịch được.
- Biểu tượng dịch chỉ cho chọn bằng chuột; chọn bằng bàn phím thì dùng ⌥T.
- Giới hạn độ dài khoảng 5.000 byte; đoạn dài dịch mất thời gian (1 KB ≈ 10–20 giây).
- Bản dịch EN → VI chính xác nhưng hơi trang trọng (giới hạn của model).
- Cỡ chữ popup cố định 14 pt; phím tắt trong popup chỉ có Esc.
- Chưa notarize: chỉ dùng cá nhân; chia sẻ cho người khác cần Developer ID (xem `docs/RELEASE.md`).

## Tài liệu

`PLAN.md` (đặc tả), `docs/ARCHITECTURE.md`, `docs/BUILD.md`, `docs/TESTING.md`, `docs/COMPATIBILITY.md`, `docs/QA-REPORT.md`, `docs/PRIVACY.md`, `docs/RELEASE.md`, `docs/PROGRESS.md`.
