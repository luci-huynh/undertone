
# Local AI Translator for macOS

## 1. Mục tiêu

Sản phẩm có **hai feature độc lập, triển khai theo thứ tự**:

1. **Dịch text (Feature 1):** bôi đen chữ → bấm ⌥T → đọc bản dịch trong popup. Hoàn thành và nghiệm thu feature này trước.
2. **Live cuộc họp (Feature 2):** lấy âm thanh cuộc họp đang phát trên máy → nhận dạng giọng nói local → hiện đồng thời phụ đề gốc và bản dịch liên tục. Chi tiết tại §24; chỉ triển khai sau Feature 1.

§2–§23 giữ phạm vi **Feature 1 / MVP 0.1.0** và các milestone hiện có. Feature 2 không thay thế, không chặn nghiệm thu, không yêu cầu làm lại Feature 1. Runbook S01–S31 tiếp tục từ tiến độ thực tế; L01–L08 dành riêng cho Feature 2, chưa được phép chạy chỉ vì đã có trong plan.

**Thuật ngữ:** “streaming text” là cách hiển thị dần kết quả model; “Live cuộc họp” là luồng âm thanh → phụ đề gốc + bản dịch. Hai khái niệm không đồng nghĩa. ⌥T chỉ kích hoạt dịch đoạn text đã bôi đen, không bật/tắt Live.

### Feature 1 — Dịch text

Xây một macOS utility chạy nền, cho phép:

**Select text ở bất kỳ ứng dụng nào → gọi AI local → hiển thị bản dịch ngay trong floating popup.**

Trải nghiệm mong muốn tương tự Google Translate khi select text trên web, nhưng:

- chạy ở cấp macOS, không phụ thuộc browser;
- AI inference chạy local;
- không bắt buộc gửi nội dung lên cloud;
- phản hồi dạng streaming để giảm cảm giác chờ;
- hoạt động với Chrome, Slack, Notion, VS Code, Mail, PDF reader và các app macOS hỗ trợ Accessibility.

Luồng chính:

```text
User selects text
        ↓
macOS detects selected text
        ↓
Small translate trigger / keyboard shortcut
        ↓
Floating popup
        ↓
Local Ollama API
        ↓
Local translation model
        ↓
Streaming translated text
        ↓
Copy / Close
```

---

# 2. Core Features

## F01 — Local AI inference

Toàn bộ translation inference chạy qua Ollama trên máy.

```text
macOS App
    ↓
localhost
    ↓
Ollama
    ↓
Local LLM
```

Không phụ thuộc OpenAI API cho translation runtime.

App cần:

- kiểm tra Ollama có đang chạy hay không;
- kiểm tra model cần thiết đã tồn tại chưa;
- hiển thị lỗi dễ hiểu nếu Ollama/model chưa sẵn sàng;
- không crash nếu Ollama unavailable.

Backend mặc định:

```text
http://localhost:11434
```

Model phải configurable, không hard-code architecture vào một model duy nhất.

---

# 3. F02 — Translate selected text ở bất kỳ app nào

App chạy background/menu bar.

Khi user select:

```text
Hello, this payment has already been processed.
```

ở:

- Chrome
- Safari
- Slack
- Notion
- VS Code
- Mail
- Pages
- PDF reader
- hoặc app hỗ trợ macOS Accessibility

app phải có khả năng lấy selected text.

Implementation chính:

```text
macOS Accessibility API
AXUIElement
```

Không sử dụng browser extension làm architecture chính.

---

# 4. F03 — Quick Translate Popup

Sau khi có selection, user có thể trigger translation bằng global shortcut.

Ví dụ:

```text
⌥ + T
```

Popup xuất hiện gần vị trí text đang selected.

Ví dụ:

```text
┌─────────────────────────────────────────┐
│ English → Vietnamese                    │
│                                         │
│ Thanh toán này đã được xử lý.           │
│                                         │
│ [ Copy ]                         [ × ]   │
└─────────────────────────────────────────┘
```

Popup phải:

- floating trên app hiện tại;
- không làm app hiện tại mất focus một cách khó chịu;
- đóng bằng `Esc`;
- copy bằng button;
- tự resize theo content;
- giới hạn max width/height;
- text dài có scroll;
- có loading state.

Recommended implementation:

```text
NSPanel
+
SwiftUI content
```

---

# 5. F04 — Streaming bản dịch text

Không chờ model generate toàn bộ response rồi mới render.

Ollama response phải được consume dưới dạng stream.

Ví dụ:

```text
Phương
Phương thức thanh
Phương thức thanh toán này
Phương thức thanh toán này đã được xử lý.
```

UI update liên tục.

Mục tiêu UX:

```text
Select
→ trigger
→ popup immediately
→ token bắt đầu xuất hiện
```

Latency perception quan trọng hơn raw throughput.

---

# 6. F05 — Automatic Language Detection

App tự detect source language.

MVP ưu tiên:

```text
English ↔ Vietnamese
```

Rule:

```text
English input
→ Vietnamese output

Vietnamese input
→ English output
```

User không cần chọn language thủ công trong normal workflow.

Settings sau này có thể cho phép:

```text
Auto → Vietnamese
Auto → English
Auto → Preferred Language
```

---

# 7. F06 — Global Keyboard Shortcut

Global shortcut phải hoạt động khi app đang chạy background.

Default:

```text
⌥ + T
```

Flow:

```text
Select text
↓
⌥ + T
↓
Read selected text
↓
Translate
↓
Popup
```

Không bắt user:

```text
Right click
→ Services
→ Translate
```

trong normal workflow.

---

# 8. F07 — Menu Bar App

Application không cần Dock window mặc định.

Status:

```text
○ Local Translator
```

Menu:

```text
Local Translator

Ollama: Connected
Model: <current model>

Settings...
Open Ollama
Quit
```

App tự chạy background.

Có option:

```text
Launch at Login
```

---

# 9. F08 — Privacy / Offline-first

Mặc định:

```text
Selected text
      ↓
localhost
      ↓
Ollama
```

Không gửi selected text tới:

- OpenAI
- Google Translate
- analytics service
- external logging

Không lưu translation history trong MVP.

Nếu cần log debug:

```text
metadata only
```

không log full selected text.

---

# 10. UX Flow

Normal user flow phải ngắn đúng ba bước:

```text
1. Select text
2. Press ⌥T
3. Read translation
```

Ví dụ:

```text
Slack

"I don't think changing the title is necessary."

             select

⌥T

┌─────────────────────────────────────────┐
│ EN → VI                                 │
│                                         │
│ Tôi không nghĩ rằng việc thay đổi tiêu  │
│ đề là cần thiết.                        │
│                                         │
│ Copy                                ×   │
└─────────────────────────────────────────┘
```

Không mở browser.

Không switch application.

Không mở ChatGPT.

---

# 11. Architecture

```text
┌─────────────────────────────────────────┐
│                macOS                    │
│                                         │
│ Chrome / Slack / Notion / VS Code      │
│                  │                      │
│             selected text               │
│                  │                      │
│                  ▼                      │
│        Accessibility Service            │
│                  │                      │
│                  ▼                      │
│        Selection Coordinator            │
│                  │                      │
│       Global Keyboard Shortcut          │
│                  │                      │
│                  ▼                      │
│           Translation Service           │
│                  │                      │
│            HTTP streaming               │
│                  ▼                      │
│       localhost:11434 / Ollama          │
│                  │                      │
│                  ▼                      │
│         Local Translation Model         │
│                  │                      │
│              streaming                  │
│                  ▼                      │
│         Floating NSPanel Popup          │
└─────────────────────────────────────────┘
```

---

# 12. Tech Stack

## Native app

```text
Swift
SwiftUI
AppKit
```

Không dùng Electron cho MVP.

Reason:

- native Accessibility integration;
- global shortcuts;
- NSPanel control;
- memory footprint thấp;
- startup nhanh;
- menu bar integration tốt;
- macOS permissions dễ quản lý hơn.

## macOS APIs

Main components:

```text
AXUIElement
Accessibility API
NSWorkspace
NSPanel
NSEvent / global shortcut
NSPasteboard
URLSession
```

Nếu cần xác định selection bounds:

```text
kAXSelectedTextRangeAttribute
kAXBoundsForRangeParameterizedAttribute
```

Fallback strategy cần được implement vì không phải app nào cũng expose Accessibility giống nhau.

---

# 13. Internal Modules

Structure đề xuất:

```text
LocalTranslator/
│
├── App/
│   ├── LocalTranslatorApp.swift
│   └── AppDelegate.swift
│
├── Accessibility/
│   ├── AccessibilityPermissionManager.swift
│   ├── SelectedTextProvider.swift
│   └── SelectionBoundsProvider.swift
│
├── Translation/
│   ├── TranslationService.swift
│   ├── OllamaClient.swift
│   ├── TranslationRequest.swift
│   └── LanguageDetector.swift
│
├── Popup/
│   ├── TranslationPanel.swift
│   ├── TranslationPopupView.swift
│   └── PopupPositioner.swift
│
├── Shortcut/
│   └── GlobalShortcutManager.swift
│
├── MenuBar/
│   └── MenuBarView.swift
│
├── Settings/
│   ├── SettingsView.swift
│   └── AppSettings.swift
│
└── Utils/
```

Giữ Accessibility, Ollama và UI tách biệt.

---

# 14. Error Handling

## Accessibility permission missing

Hiển thị:

```text
Local Translator needs Accessibility permission
to read selected text.

[Open System Settings]
```

## Ollama offline

```text
Ollama is not running.

[Retry]
```

## Model unavailable

```text
Translation model is not installed.
```

Không auto-download model trong background ở MVP.

## Nothing selected

```text
No text selected.
```

Popup nhỏ rồi auto dismiss.

---

# 15. Performance Requirements

Target:

```text
Shortcut → popup:
< 150 ms

Popup → request Ollama:
immediately

First translated token:
as fast as local model allows
```

App itself phải lightweight.

Không load model.

Ollama chịu trách nhiệm model lifecycle của dịch text. Nhận dạng giọng nói local của Feature 2 có runtime/model riêng được chọn ở L01; không áp dụng yêu cầu “App không load model” cho runtime nhận dạng này.

---

# 16. MVP Scope — Feature 1: Dịch text

Version:

```text
0.1.0
```

MVP chỉ cần hoàn thành:

1. Menu bar app
2. Accessibility permission
3. Read selected text
4. Global shortcut
5. Floating popup
6. Connect Ollama
7. Translate EN ↔ VI
8. Stream response
9. Copy translation
10. Error handling cơ bản

Không thêm những feature ngoài scope cho đến khi 10 mục này stable.

---

# 17. Out of Scope — MVP dịch text

Chưa làm:

```text
OCR
Screen translation
Translation history
Cloud sync
Browser extension
iOS
Windows
Multiple translation providers
User account
Analytics
RAG
Agent workflow
Rewrite
Grammar correction
Summarize
Explain
```

Live cuộc họp được lên kế hoạch riêng ở §24, sau khi nghiệm thu MVP dịch text; không nằm trong danh sách loại trừ trên. Các mục còn lại chỉ xem xét khi có yêu cầu riêng.

---

# 18. Development Milestones

## Milestone 1 — macOS shell

Build:

```text
Menu bar app
Global shortcut
Accessibility permission
```

Acceptance:

```text
⌥T
```

được nhận từ bất kỳ app nào.

---

## Milestone 2 — Selected Text

Build:

```text
SelectedTextProvider
SelectionBoundsProvider
```

Test với:

```text
Safari
Chrome
Slack
VS Code
Notes
Preview
```

Acceptance:

```text
select text → ⌥T
```

app đọc được đúng text.

---

## Milestone 3 — Popup

Build:

```text
NSPanel
SwiftUI popup
position near selection
Esc close
Copy
```

Tạm thời chưa cần AI.

Popup chỉ show selected text.

Acceptance:

```text
Select
→ ⌥T
→ popup gần selection
```

---

## Milestone 4 — Ollama

Implement:

```text
OllamaClient
```

support:

```text
health check
model configuration
streaming generation
cancel request
errors
```

Acceptance:

```text
String
→ Ollama
→ streamed String
```

---

## Milestone 5 — Translation

Implement translation pipeline:

```text
selected text
↓
detect EN/VI
↓
build translation request
↓
Ollama
↓
stream translation
↓
popup
```

Acceptance:

```text
English → Vietnamese
Vietnamese → English
```

---

## Milestone 6 — Polish

Handle:

```text
long text
multiple paragraphs
rapid repeated shortcuts
cancel previous translation
Ollama offline
model missing
permission revoked
different screen
multi-monitor
popup screen boundaries
```

---

# 19. Tests

Unit tests:

```text
LanguageDetectorTests
OllamaClientTests
TranslationServiceTests
PopupPositionerTests
```

Manual integration matrix:

```text
Safari
Chrome
Slack
Notion
VS Code
Apple Notes
Mail
Preview PDF
```

Test cases:

```text
short sentence
long paragraph
multiline selection
English
Vietnamese
mixed language
emoji
Unicode
code snippets
empty selection
```

---

# 20. Definition of Done — MVP dịch text

MVP được xem là hoàn thành khi:

```text
Open Slack
↓
select English text
↓
press ⌥T
↓
popup appears beside selection
↓
Vietnamese translation streams in
↓
press Copy
```

và:

```text
Internet disconnected
```

workflow trên vẫn hoạt động nếu Ollama/model đã có sẵn trên máy.

---

# 21. Codex Development Strategy

Codex chịu trách nhiệm:

```text
inspect repo
implement features
run xcodebuild
run tests
fix compilation errors
refactor
update documentation
```

Không giao toàn project trong một prompt khổng lồ.

Chia task theo milestones.

Mỗi milestone:

```text
Implement
↓
Build
↓
Test
↓
Review diff
↓
Commit
↓
Next milestone
```

---

# 22. AGENTS.md

Tạo file root:

```text
AGENTS.md
```

với rule:

```text
# Project

Native macOS local AI translation utility.

# Stack

- Swift
- SwiftUI
- AppKit
- macOS Accessibility API
- Ollama HTTP API

# Architecture

Keep these concerns separated:

- Accessibility
- Translation
- Ollama networking
- Popup UI
- Global shortcut
- Settings

# Product principles

- Local-first
- Privacy-first
- Low latency
- Minimal UI
- Native macOS UX

# Constraints

- Do not introduce Electron.
- Do not add cloud translation.
- Do not send user-selected text outside localhost.
- Do not add features outside the current milestone.
- Do not store selected text or translations.
- Prefer native Apple APIs.
- Keep Ollama models configurable.

# Development

Before finishing every task:

1. Build the app.
2. Run relevant tests.
3. Fix warnings introduced by the change.
4. Summarize changed files.
5. Report unresolved limitations.
```

---

# 23. First Codex Task

Sau khi tạo empty Xcode/macOS project, giao Codex:

```text
Read AGENTS.md and inspect the repository.

Implement Milestone 1 only.

Goal:
Create the foundation of a native macOS menu-bar application for Local Translator.

Requirements:
- Swift + SwiftUI/AppKit.
- Run as a menu-bar application.
- Add Accessibility permission checking.
- Provide a button that opens the appropriate macOS System Settings page when permission is missing.
- Register Option+T as the global translation shortcut.
- For now, when Option+T is triggered, log a simple event. Do not implement text selection, Ollama, or translation yet.
- Keep accessibility, shortcut, and UI concerns separated.
- Add appropriate unit-testable abstractions where useful.
- Build using xcodebuild after implementation.
- Fix compile errors before finishing.
- Do not implement features belonging to later milestones.

At the end report:
- architecture created
- files changed
- build command
- build result
- known limitations
```

Sau đó lần lượt giao:

```text
Milestone 2
Milestone 3
Milestone 4
Milestone 5
Milestone 6
```

Không để Codex tự nhảy scope.

---

# 24. Feature 2 — Live cuộc họp (sau khi hoàn thành dịch text)

## 24.1. Phạm vi đã chốt

- Nguồn là **âm thanh cuộc họp đang phát trên máy**, từ app hoặc trình duyệt người dùng chọn; không mở mic riêng để thu giọng người dùng.
- Nhận dạng giọng nói (ASR) và dịch chạy **hoàn toàn local**. Dịch qua Ollama loopback; ASR dùng runtime/model on-device, không yêu cầu phải qua Ollama.
- Trong lúc cuộc họp diễn ra, hiện **phụ đề ngôn ngữ gốc phía trên và bản dịch phía dưới**, cùng cửa sổ LIVE theo mẫu người dùng. Phụ đề gốc xuất hiện ngay khi có kết quả nhận dạng; không chờ bản dịch.
- Hướng ban đầu theo mẫu đã cung cấp: **tiếng Anh → tiếng Việt**. Các hướng khác chỉ thêm sau khi được yêu cầu; không ảnh hưởng EN ↔ VI của dịch text.
- Có chọn nguồn, Start và Stop riêng. Không dùng ⌥T để điều khiển Live; không bắt người dùng bôi đen hay thao tác mỗi câu.
- Chỉ thu khi người dùng Start. Stop, đóng cửa sổ Live hoặc quit phải dừng capture, hủy việc đang chờ và xóa nội dung/buffer của phiên.
- Không lưu audio, transcript hay bản dịch thành lịch sử/file; không ghi nội dung vào log, analytics hoặc gửi ra ngoài máy. Buffer tạm trong RAM phải có giới hạn và được giải phóng khi dừng.
- Internet của app họp không thuộc pipeline dịch; bản thân ASR/dịch phải chạy offline sau khi đã cài đủ model. Không tự chuyển sang cloud khi thiếu model hoặc máy chậm.

## 24.2. Luồng và hiển thị

```text
Chọn nguồn cuộc họp → Start Live
                            ↓
                  Audio capture trên máy
                            ↓
                 ASR local liên tục
                            ↓
           Phụ đề gốc (partial → finalized)
                            ↓
           Dịch các đoạn ổn định qua Ollama local
                            ↓
                 Bản dịch cập nhật liên tục
```

Capture và ASR tiếp tục trong lúc đoạn trước đang được dịch. “Song song” nghĩa là người dùng nhìn thấy cả hai phần cùng cập nhật; bản dịch có độ trễ xử lý, không hứa xuất hiện cùng thời điểm với âm thanh.

```text
┌──────────────────────────────────────────────────────┐
│ LIVE                                         [Stop]  │
│                                                      │
│ EN  We expect the migration to finish                 │
│     sometime next week.                              │
│                                                      │
│ VI  Chúng tôi dự kiến quá trình migration             │
│     sẽ hoàn tất vào khoảng tuần sau.                 │
└──────────────────────────────────────────────────────┘
```

- Cửa sổ nổi, di chuyển/đổi kích thước được; hai khối dễ đọc, wrap/scroll cho câu dài. Không giành focus liên tục khỏi app họp.
- Phân biệt đang nghe, đang nhận dạng, đang dịch, không có âm thanh và lỗi. Không tạo phụ đề khi im lặng.
- Ghép phụ đề gốc và bản dịch bằng cùng đoạn/phiên: không đặt bản dịch câu trước dưới câu mới như thể là một cặp. Khi chờ dịch đoạn mới, hiện trạng thái chờ rõ ràng.
- Bản nhận dạng tạm có thể được sửa; khi nguồn thay đổi, bỏ kết quả dịch cũ tương ứng. Không dịch lại toàn bộ transcript sau mỗi token, không tạo hàng đợi vô hạn khi người nói nhanh.
- Giữ số đoạn hiển thị gần nhất có giới hạn trong RAM; không biến cửa sổ thành tính năng lưu transcript.

## 24.3. Bảo toàn dịch text

- Hoàn tất S01–S31 và người dùng nghiệm thu Feature 1 trước khi bắt đầu L01. Tài liệu này không cấp quyền triển khai Live trước thời điểm đó.
- Giữ nguyên ⌥T, AX selection, popup text, Copy/Close, settings/model text và dữ liệu cấu hình hiện tại. Không tạo lại project hoặc refactor text trước chỉ để chuẩn bị cho Live.
- Live có trạng thái phiên, capture, hàng đợi và cửa sổ riêng. Start/Stop Live không được hủy request hay đóng popup text; ⌥T không được reset phiên Live.
- Có thể tái sử dụng Ollama client nếu phù hợp, nhưng cancellation phải thuộc từng request. Khi dùng chung tài nguyên model, giữ text đáp ứng được và giới hạn backlog Live; chọn cơ chế đơn giản sau khi đo ở L01/L06.
- Khi Live tắt hoặc thiếu quyền/model audio, Feature 1 vẫn hoạt động bình thường. Không hỏi quyền audio lúc chỉ dùng dịch text.
- Mọi thay đổi code dùng chung ở L01–L08 phải chạy regression của dịch text. Chưa có bằng chứng regression pass thì chưa nghiệm thu bước đó.

## 24.4. Quyết định kỹ thuật để lại đúng thời điểm

L01 khảo sát API capture native, phạm vi lọc app/trình duyệt thực tế, quyền macOS, ASR runtime/model local, license, tài nguyên và khả năng cập nhật liên tục trên máy đích. Chỉ chốt sau khi kiểm chứng; không thêm dependency/model hoặc nâng minimum macOS của dịch text ngay trong lượt sửa spec này.

Nếu không thể cô lập nguồn cuộc họp, báo rõ giới hạn; không âm thầm thu toàn bộ system audio hoặc mic. Không cam kết loại bỏ tiếng tự nghe đã nằm trong luồng audio phát ra của app họp. Thay đổi phạm vi capture hoặc minimum macOS phải được người dùng duyệt trước implementation phụ thuộc.

Latency được đo riêng: âm thanh → phụ đề gốc, đoạn nguồn ổn định → bản dịch, tổng end-to-end và backlog. L01 đề xuất ngân sách latency/tài nguyên để người dùng chốt trước pipeline hoàn chỉnh; L07 đo p50/p95 thực tế. Mục tiêu <150 ms của popup text không phải cam kết latency nhận dạng/dịch cuộc họp.

Chưa bao gồm: thu mic riêng, ghi âm, xuất/lưu transcript, speaker diarization, tóm tắt cuộc họp, bot tham gia họp, dịch giọng nói thành tiếng hoặc cloud fallback.

## 24.5. Definition of Done — Live cuộc họp

1. Chọn nguồn cuộc họp được hỗ trợ → Start → thấy tiếng Anh gốc và bản dịch tiếng Việt cập nhật trong cùng cửa sổ như mẫu, không thao tác theo từng câu.
2. Phụ đề gốc không đợi dịch; các cặp nguồn/bản dịch đúng đoạn, không nhận kết quả từ phiên đã dừng. Chất lượng được người dùng đánh giá bằng mẫu audio tổng hợp/được phép dùng.
3. Stop/đóng/quit dừng capture và giải phóng buffer; thử Start/Stop liên tiếp, im lặng, câu dài, ngắt lời, mất nguồn, thu hồi quyền, thiếu model và Ollama lỗi có trạng thái rõ.
4. Offline sau setup vẫn nhận dạng và dịch được với audio kiểm thử phát trên máy. Không yêu cầu cuộc họp qua Internet tiếp tục khi mạng bị ngắt.
5. Kiểm tra code + network + storage/log xác nhận pipeline local, không tự thu mic và không lưu nội dung. Không chỉ dùng offline test để kết luận riêng tư.
6. Đo latency/backlog/CPU/RAM trên máy đích và chạy phiên ít nhất 30 phút; đạt ngưỡng đã chốt tại L01, không tăng hàng đợi/bộ nhớ vô hạn. Thiếu số đo hoặc ngưỡng chưa được duyệt thì chưa PASS.
7. Dịch text vẫn pass regression khi Live tắt, bật và vừa Stop, bao gồm ⌥T, stream, cancel, Copy/Close và offline. Báo giới hạn theo từng app họp đã kiểm tra; chưa test thì NOT RUN.
8. Người dùng nghiệm thu Feature 2 riêng. Hoàn tất dịch text không đồng nghĩa Live đã hoàn tất, và ngược lại.
