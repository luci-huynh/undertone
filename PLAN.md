
# Local AI Translator for macOS

## 1. Mục tiêu

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

# 5. F04 — Live / Streaming Translation

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

Ollama chịu trách nhiệm model lifecycle.

---

# 16. MVP Scope

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

# 17. Out of Scope — MVP

Chưa làm:

```text
OCR
Screen translation
Voice translation
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

Những feature này chỉ xem xét sau MVP.

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

# 20. Definition of Done — MVP

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