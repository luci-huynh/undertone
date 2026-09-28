# Undertone

Trước đây là Local Translator. Từ 0.3.0: app `Undertone.app`, bundle ID `local.chienhuynh.Undertone`, module Swift `Undertone`. Thư mục source và project Xcode vẫn tên `LocalTranslator` (chỉ là tên nội bộ). Vì bundle ID mới, macOS coi đây là app mới: cần cấp lại quyền Accessibility và System Audio Recording, và bật lại Mở cùng macOS.

Ứng dụng thanh menu cho macOS, chạy **hoàn toàn trên máy**:

- **Dịch chữ**: bôi đen chữ ở bất kỳ app nào → bấm **⌥T** (hoặc biểu tượng dịch cạnh con trỏ) → đọc bản dịch hiện dần trong popup. Dịch qua [Ollama](https://ollama.com); chữ không rời khỏi máy.
- **Live cuộc họp** (macOS 26+): phụ đề tiếng Anh và bản dịch tiếng Việt ngay trong lúc họp trên Microsoft Teams, Google Meet (Chrome) hoặc Slack huddle. Chỉ nghe âm thanh của app họp đã chọn, không dùng micro, không lưu gì.

Phiên bản: **0.3.0 (build 4)** — dịch chữ + Live cuộc họp, dùng cá nhân (xem `docs/RELEASE.md`). Bản trước còn giữ (tên cũ Local Translator): 0.2.1 (build 3) và 0.2.0 (build 2) — cách quay lại ở cuối trang.

## Yêu cầu

- macOS 14 trở lên cho dịch chữ; **macOS 26 trở lên cho Live** (đã kiểm tra trên macOS 27.0, Apple M5, 24 GB).
- Ollama chạy trên máy tại `http://127.0.0.1:11434`.
- Model `translategemma:12b` (8,1 GB; khi đang dùng chiếm khoảng 8–9 GB RAM). Live dùng chung model này.
- Live: model nhận dạng giọng nói tiếng Anh của macOS (chạy trên máy, khoảng 350 MB). Nếu máy chưa có, lần bấm Start đầu tiên macOS tải một lần (cửa sổ Live hiện phần trăm); sau đó dùng được offline. Dịch chữ không cần model này.
- Để build: Xcode 27 trở lên và một Apple ID (Personal Team là đủ).

## Cài đặt

1. **Ollama và model**
   ```sh
   ollama pull translategemma:12b
   ```
   App không tự tải model dịch.
2. **Build và cài app**
   ```sh
   xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Release \
     -destination "generic/platform=macOS" -archivePath .build/Undertone-0.3.0-4.xcarchive archive
   ditto .build/Undertone-0.3.0-4.xcarchive/Products/Applications/Undertone.app /Applications/Undertone.app
   open /Applications/Undertone.app
   ```
   Trên máy khác hoặc với Apple ID khác: mở project trong Xcode → target LocalTranslator → Signing & Capabilities → chọn Team của bạn (đổi bundle ID nếu Xcode báo trùng). Chi tiết: `docs/RELEASE.md`.
3. **Quyền Accessibility** (bắt buộc cho dịch chữ, để đọc chữ đã chọn): menu Undertone → Settings… → Quyền Accessibility → *Xin quyền…*, hoặc System Settings → Privacy & Security → Accessibility → bật Undertone.
4. **Quyền cho Live** (chỉ khi dùng Live): lần đầu bấm **Start**, macOS hỏi quyền ghi âm thanh hệ thống → cho phép. Quyền nằm ở System Settings → Privacy & Security → Screen & System Audio Recording → mục **System Audio Recording Only**. App không bao giờ hỏi quyền micro, và không hỏi quyền âm thanh khi bạn chỉ dùng dịch chữ.
5. **Tuỳ chọn**: Settings → Khởi động → *Mở cùng macOS*.

## Sử dụng — dịch chữ

| Thao tác | Kết quả |
|---|---|
| Bôi đen chữ → **⌥T** | Popup cạnh vùng chọn, bản dịch hiện dần |
| Kéo chuột hoặc nhấp đúp để bôi đen → bấm **biểu tượng dịch** cạnh con trỏ | Như ⌥T (tắt được trong Settings → Nút dịch khi bôi đen) |
| Chiều dịch | Tự nhận diện: English → Vietnamese, Vietnamese → English, ngôn ngữ khác → Vietnamese. Chữ quá ngắn/mơ hồ: đoán, tiêu đề ghi “(guessed)” |
| **⇄** | Dịch lại theo chiều ngược, chỉ cho lần này |
| **↻** / **Retry** | Dịch lại cùng đoạn (sau khi xong / khi lỗi) |
| **Copy** | Chép bản dịch đã xong (nút đổi thành ✓) |
| Kéo chỗ trống của popup | Di chuyển popup; nó giữ chỗ mới đến khi đóng |
| **Esc** hoặc × | Đóng, huỷ lượt đang dịch |

## Sử dụng — Live cuộc họp

| Thao tác | Kết quả |
|---|---|
| Menu → **Live Meeting Translation…** | Mở cửa sổ Live; không lấy focus khỏi app họp |
| Chọn nguồn: *Microsoft Teams*, *Google Chrome (Google Meet)* hoặc *Slack (huddles)* → **Start** (hoặc Return) | Phụ đề tiếng Anh (EN) hiện ngay khi nhận dạng; bản dịch tiếng Việt (VI, chữ xanh xám) hiện bên dưới từng câu sau khoảng 1,5–4 giây |
| **Stop**, đóng cửa sổ Live, hoặc Quit | Dừng nghe, xoá phụ đề, bản dịch và bộ đệm âm thanh của phiên |
| Nút ghim 📌 | Giữ cửa sổ nổi trên các cửa sổ khác, kể cả app họp toàn màn hình (mặc định bật); bấm lại để tắt. Cửa sổ thu nhỏ (minimize), đổi cỡ và di chuyển được; nhớ vị trí |
| Cuộn lên đọc câu cũ | Cửa sổ ngừng tự cuộn; cuộn về cuối thì tự theo lại |
| Khi Live đang chạy | Menu hiện “Live: On — <tên app>”, để không quên phiên đang thu nhỏ |

Dòng trạng thái: *Listening* (đang nghe), *Listening — no sound* (app họp đang im), *<app> isn't running*, lỗi quyền (kèm nút *Open System Settings*), và *Translation: …* khi dịch lỗi (kèm nút *Open Ollama* nếu Ollama tắt). Nếu người nói nhanh hơn tốc độ dịch, tối đa 3 câu chờ (nhiều hơn thì gộp lại); câu chờ quá 30 giây ghi “Not translated — Live fell behind”. Khi đang Live, ⌥T vẫn được ưu tiên: bản dịch Live tạm dừng rồi chạy tiếp.

## Menu

Trạng thái Ollama và model, Live: On (khi đang chạy), Live Meeting Translation…, Settings…, Open Ollama, Quit.

## Riêng tư

- Dịch chữ: chữ đã chọn chỉ gửi tới Ollama trên máy (`127.0.0.1`).
- Live: chỉ âm thanh của app họp đã chọn (không micro); nhận dạng giọng nói bằng model của macOS trên máy; dịch qua cùng Ollama trên máy. Chỉ giữ trong RAM tối đa 30 giây âm thanh và 50 câu; xoá khi Stop, đóng cửa sổ hoặc Quit.
- Không cloud, không analytics, không lịch sử, không file transcript; log chỉ có số liệu (số ký tự, mili-giây, trạng thái). Chi tiết và bằng chứng: `docs/PRIVACY.md`, `docs/LIVE-QA.md`.

## Khắc phục sự cố

| Thông báo / hiện tượng | Cách xử lý |
|---|---|
| “Undertone needs Accessibility permission…” | Bấm *Open System Settings* và bật quyền. Sau khi build lại hoặc chuyển app sang máy khác có thể phải cấp lại |
| “Ollama is not running.” | Mở Ollama (menu → Open Ollama) rồi bấm *Retry* |
| “Translation model is not installed.” | `ollama pull translategemma:12b`, hoặc chọn model khác trong Settings |
| “The model took too long to start.” / “Ollama stopped responding.” | Thường do thiếu RAM hoặc Ollama bận; đợi rồi *Retry* |
| “Selected text is too long to translate at once.” | Giới hạn khoảng 5.000 ký tự tiếng Anh (ít hơn với tiếng Việt); chọn đoạn ngắn hơn |
| “Can't read selected text in this app.” | App đó không cho đọc chữ qua Accessibility |
| Chrome, Brave, Slack, Notion không đọc được ở lần đầu | Lần đầu sau khi mở các app này cần khoảng 10–30 giây để bật chế độ trợ năng; thử lại sau đó |
| ⌥T không phản ứng | Settings → Phím tắt: nếu báo trùng, đóng app đang dùng ⌥T rồi *Thử lại*. Chỉ chạy một bản Undertone cùng lúc |
| Lần dịch đầu tiên chậm (3–6 giây) | Ollama đang nạp model; các lần sau nhanh (model được giữ 30 phút) |
| Live: “<app> isn't running” | Mở app họp; Live tự nhận khi app đó phát âm thanh |
| Live: “The app is playing but no sound arrives…” hoặc “Audio capture was refused…” | Bấm *Open System Settings* → bật Undertone ở **System Audio Recording Only** → Stop rồi Start |
| Live: “Listening — no sound” | App họp chưa phát âm thanh (không ai nói, hoặc bị tắt tiếng trong app họp) |
| Live: “Translation: Ollama is not running.” | Bấm *Open Ollama*; các câu mới sẽ được dịch tiếp |
| Live: “Speech recognition stopped. Press Start to try again.” | Bấm Start lại |
| Live: menu ghi “Live Meeting Translation needs macOS 26” | Live cần macOS 26 trở lên; dịch chữ vẫn dùng bình thường |

## Giới hạn đã biết

- Safari: trước 0.2.0 không đọc được chữ đã chọn; 0.2.0 sửa một nguyên nhân có thể (tiến trình nội dung web bị hiểu nhầm là app khác) nhưng **chưa kiểm tra lại trên Safari**.
- Chromium/Electron (Chrome, Brave, Slack, Notion) cần khởi động trợ năng ở lần đầu; popup có thể hiện ở con trỏ thay vì cạnh vùng chọn.
- Không OCR: PDF scan không có lớp chữ, ảnh và video không dịch được.
- Biểu tượng dịch chỉ cho chọn bằng chuột; chọn bằng bàn phím thì dùng ⌥T.
- Giới hạn độ dài khoảng 5.000 byte; đoạn dài dịch mất thời gian (1 KB ≈ 10–20 giây).
- Bản dịch EN → VI chính xác nhưng hơi trang trọng (giới hạn của model); đôi khi model dịch luôn từ viết tắt (ví dụ “QA”) thay vì giữ nguyên.
- Cỡ chữ popup cố định 14 pt; phím tắt trong popup chỉ có Esc.
- Live chỉ dịch **tiếng Anh → tiếng Việt**; không phân biệt người nói; không dịch giọng của chính bạn (app họp không phát lại giọng bạn).
- Live với Chrome nghe **mọi tab Chrome**, không chỉ tab Google Meet: tắt tiếng các tab khác khi họp.
- Live đã kiểm tra thực tế với Teams và Chrome; **Slack huddle chưa kiểm tra**. Tai nghe có micro (headset) làm đồng hồ âm thanh chưa kiểm tra.
- Live giữ 50 câu gần nhất; không lưu hoặc xuất transcript (theo thiết kế).
- ⌥T không dịch chữ bên trong cửa sổ Live (theo thiết kế).
- Chưa notarize: chỉ dùng cá nhân; chia sẻ cho người khác cần Developer ID (xem `docs/RELEASE.md`).

## Quay lại bản trước (tên cũ Local Translator)

Quit Undertone, rồi (0.2.1; thay bằng `LocalTranslator-0.2.0-2.zip` nếu muốn 0.2.0):

```sh
ditto -x -k .build/release/LocalTranslator-0.2.1-3.zip /tmp/lt-0.2.1
rm -rf /Applications/Undertone.app
ditto /tmp/lt-0.2.1/LocalTranslator.app /Applications/LocalTranslator.app
open /Applications/LocalTranslator.app
```

Bản cũ dùng bundle ID `local.chienhuynh.LocalTranslator`: quyền của ID này đã bị xoá khi chuyển sang Undertone và cài đặt đã được chép sang ID mới, nên phải cấp lại quyền; cài đặt quay về mặc định trừ khi chép ngược (`defaults export local.chienhuynh.Undertone - | defaults import local.chienhuynh.LocalTranslator -`). Không chạy hai app cùng lúc (tranh ⌥T). Checksum: `.build/release/SHA256SUMS`. Bản 0.1.0 đã được xoá theo yêu cầu; nếu cần, build lại từ commit `3b3290d`.

## Tài liệu

`PLAN.md` (đặc tả), `docs/ARCHITECTURE.md`, `docs/BUILD.md`, `docs/TESTING.md`, `docs/COMPATIBILITY.md`, `docs/QA-REPORT.md`, `docs/PRIVACY.md`, `docs/PERMISSIONS.md`, `docs/LIVE-DESIGN.md`, `docs/LIVE-QA.md`, `docs/RELEASE.md`, `docs/RELEASE-CHECKLIST.md`, `docs/PROGRESS.md`, `CHANGELOG.md`.
