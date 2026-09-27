# Đối chiếu PLAN với runbook — S05

Mapping là kế hoạch kiểm chứng, không chứng nhận feature đã làm hoặc cấp quyền cho bước tương lai. S01–S04 đã có bằng chứng trong PROGRESS.md; toàn bộ feature sản phẩm vẫn chưa triển khai. Các số § dưới đây là mục của PLAN.md.

## Yêu cầu sản phẩm

| PLAN | Yêu cầu / tiêu chí | Bước thực hiện và kiểm chứng |
|---|---|---|
| §1, §10 | Select → ⌥T → đọc popup, không mở browser/ChatGPT hay switch app | S09–S14, S20; review focus S13, QA S27, nghiệm thu S31 |
| §2 F01 | Ollama local, localhost:11434, model configurable, offline/model missing không crash | Môi trường S15–S17; client/readiness/model settings S18; errors S23; offline S27–S28/S31 |
| §3 F02 | Background/menu bar, selected text qua AX; không browser extension | S06–S10; tương thích/fallback S11; QA S27 |
| §4 F03 | Floating gần selection, tránh mất focus, Esc/Close/Copy, loading | Bounds S12; panel S13; ghép luồng S14; stream S20; polish S25 |
| §4 F03 | Resize, max width/height, scroll nội dung dài | S13 nền tảng; S25 hoàn thiện; S27 thử màn nhỏ/multi-monitor |
| §5 F04 | Render stream liên tục; popup không chờ toàn bộ response | Parser S19, UI S20; cold/warm latency S27 |
| §6 F05 | Detect local, EN→VI và VI→EN, không chọn tay cho case thông thường | S21 routing, S22 prompt, S26 tests, S27 chất lượng; ambiguous UX cần duyệt trước code |
| §7 F06 | Global ⌥T hoạt động ở nền, không dùng Services làm luồng chính | S09 đăng ký/conflict/repeat/lifecycle; S14 pipeline; S27 integration |
| §8 F07 | Menu bar, không cửa sổ Dock mặc định; Settings/Open Ollama/Quit; trạng thái model/runtime | S06 shell; S18 trạng thái/settings thật; S25 polish; S27 lifecycle |
| §8 F07 | Option Launch at Login | Bổ sung mapping rõ vào S25 trong phạm vi settings của PLAN; hiện chưa có bước riêng trong runbook. Test bật/tắt/trạng thái và login thật khi được người dùng cho phép |
| §9 F08 | Không cloud, analytics, external logging, history; debug metadata only | Thiết kế S05; implementation S10/S18–S23; audit code/storage/network S28; offline S17/S27/S31 |
| §11–§13 | Swift/SwiftUI/AppKit, AX, NSPanel, URLSession; chia Accessibility/translation/network/UI/shortcut/settings | S03 baseline; S05 thiết kế; S06 interfaces; adapters tại S07–S22; không Electron |
| §12 | Selection bounds và fallback vì AX không đồng nhất | S11 text fallback policy; S12 bounds→mouse fallback; không mặc định clipboard fallback |
| §14 | Thiếu Accessibility → giải thích và Open System Settings | S07, S08 permission thật/revoke; S23 recovery |
| §14 | Ollama offline → Retry; model unavailable → lỗi rõ, không tải ngầm | S18/S23; setup chủ động S15–S17; QA S27/S31 |
| §14 | Nothing selected → popup nhỏ rồi auto-dismiss | S10 phát hiện; S13–S14 UI/timer gắn request ID; S23/S25 hoàn thiện |
| §15 | Shortcut→popup <150 ms, gửi Ollama ngay, first token sớm nhất có thể | S10 timeout AX, S12–S14 panel path, S20 stream; S27 đo từ trigger, ghi cold/warm riêng. Chưa có số đo |
| §15 | Lightweight, app không load model, Ollama quản lý model | S18 ranh giới client; S27 CPU/RAM/idle; không tự định mức ngoài spec |
| §16 | Version 0.1.0, ổn định 10 mục MVP trước mở rộng | S02/S03 version; mapping MVP bên dưới; S26–S31 kiểm chứng |
| §17 | Không OCR/screen/voice/history/cloud sync/browser extension/iOS/Windows/providers/account/analytics/RAG/agent/rewrite/grammar/summarize/explain | Guardrail mọi bước; S28 audit; không tạo module cho tính năng ngoài scope |
| §19 | LanguageDetector, OllamaClient, TranslationService, PopupPositioner unit tests | Test target S06; tests logic ở bước liên quan S12/S14/S18–S23; tổng hợp S26 |
| §19 | Short/long/multiline, EN/VI/mixed, emoji/Unicode/code/empty | Fixtures tổng hợp S10/S19/S21/S22/S26; manual QA S27 |
| §3, §18, §19 | Safari, Chrome, Slack, Notion, VS Code, Mail, Pages, Apple Notes, Preview/PDF; app AX khác | S10–S12 giới hạn; matrix S27 gồm cả Pages dù danh sách §19 không nhắc lại. App chưa có → NOT RUN, không tự cài; PDF scan không text layer không thuộc OCR MVP |
| §20 | Slack EN→VI streaming→Copy vẫn chạy khi ngắt Internet và model đã sẵn | S27 + S28 + S31 trên binary thật; không thay bằng unit tests |
| §21–§23 | Làm từng milestone, build/tests/report; instructions và initial shell task | S01–S06 bootstrap, S07–S09 hoàn thành M1; Operator protocol quy định nhỏ hơn milestone, không tự commit/chuyển bước |

## 10 mục MVP và milestones

| Mục MVP §16 | Owner steps |
|---|---|
| 1 Menu bar | S06, S18, S25 |
| 2 Accessibility permission | S07–S08 |
| 3 Selected text | S10–S12 |
| 4 Global shortcut | S09 |
| 5 Floating popup | S12–S14, S25 |
| 6 Ollama | S15–S18 |
| 7 EN ↔ VI | S21–S22 |
| 8 Streaming | S19–S20 |
| 9 Copy | S13, S25 |
| 10 Basic errors | S07/S10/S18–S23 |

| Milestone §18 | Mapping / acceptance |
|---|---|
| M1 Shell | S06–S09: menu bar, AX permission, ⌥T khi nền |
| M2 Selection | S10–S12: text đúng, bounds hoặc fallback; matrix nguồn |
| M3 Popup | S13–S14: hiện selected text qua fake service, chưa AI |
| M4 Ollama | S15–S20: readiness/model, stream, cancel/error |
| M5 Translation | S21–S22: auto EN↔VI, prompt theo model; S20 có thể dùng hướng test cố định tạm thời, không báo pipeline sản phẩm hoàn tất |
| M6 Polish | S23–S28: long/multiline, rapid triggers/cancel, runtime/model/permission, screen boundaries/multi-monitor; S29–S31 đóng gói và nghiệm thu |

## Gaps, điều kiện và quyết định chưa được duyệt

- S11 không tự coi N/A: PLAN §12 thực sự yêu cầu fallback. Đề xuất mouse fallback cho bounds và unsupported UX cho text. Clipboard fallback chưa được spec xác định; phải duyệt trước khi thêm.
- S24 chỉ áp dụng nếu người dùng xác nhận small selection trigger là bắt buộc. Recommendation shortcut-only theo luồng §10 và MVP §16; việc duyệt S05 không tự thực hiện hoặc bỏ qua S24. Đến ID đó vẫn báo N/A (nếu đã chốt) và STOP.
- Launch at Login và Open Ollama dễ bị bỏ sót: mapping ở bảng trên bổ sung rõ vào S18/S25; không mở rộng ngoài PLAN. Quyền đăng ký login item thực tế thuộc bước triển khai đã duyệt.
- PLAN chưa chốt xử lý mixed/ambiguous/unsupported language. S21 phải trình UX đơn giản trước phần phụ thuộc; không âm thầm suy ra ASCII=English hoặc thêm preferred-language settings “sau này” vào MVP.
- Model tag chưa có: khảo sát S15, người dùng duyệt tag trước S17. S16 kiểm tra runtime có sẵn thay vì cài lại khi thích hợp.
- Sandbox/AX và distribution còn cần kiểm chứng: S08/S10 không được pass chỉ vì build pass; thay sandbox/entitlement cần duyệt. S28 chốt release route; S30 dự kiến N/A nếu chỉ local, vẫn STOP riêng, không có quyền upload/publish ngầm.
- Không gộp các bước vì bảng mapping dùng dải ID. S06 chỉ shell/fake/tests; fake readiness phải hiển thị chưa kiểm tra, không giả Connected.
- Outside-click dismiss, shortcut customization, launch tự bật và settings ngôn ngữ mở rộng không phải requirement MVP rõ ràng. Không tự bổ sung chỉ vì runbook nhắc ví dụ.
- Mapping không bảo đảm mọi app expose AX. Unsupported/NOT RUN phải có bằng chứng; không dùng OCR hoặc keylogging để bù.

## Review S05

Đã đối chiếu toàn bộ §1–§23, F01–F08, 10 mục MVP, sáu milestones, test matrix và DoD. Mọi mục có owner step hoặc decision gate. Flow shortcut→snapshot→route→panel→Ollama→stream được review tĩnh trong ARCHITECTURE.md, bao gồm focus và request ID. Chưa chạy manual integration hoặc test tính năng ở S05.
