# Kiến trúc đề xuất — S05

Trạng thái: thiết kế được người dùng duyệt khi yêu cầu tiếp tục S06 (“ok tiếp tục di”). Đây không phải implementation hoặc quyền thực hiện bước tiếp theo. PLAN.md là spec; xem SPEC-MAP.md để biết phạm vi và các điểm còn thiếu.

## Baseline đã quan sát

- App hiện chỉ là template SwiftUI WindowGroup, ContentView “Hello, world!”. Chưa có services, menu bar, AX, shortcut hay network.
- Project/target/shared scheme: LocalTranslator. Bundle ID local.chienhuynh.LocalTranslator; macOS tối thiểu 14.0; version 0.1.0.
- Tại S05, project bật ENABLE_APP_SANDBOX và default actor isolation MainActor. S05 không đổi project, signing, entitlement hoặc source. (Cập nhật S07: sandbox đã tắt, xem "Quyết định sandbox" cuối file.)
- Build Debug S04 thành công. Đây không phải bằng chứng khả năng AX xuyên ứng dụng, TCC, latency hay chạy trên macOS 14.

## Cấu trúc tối thiểu

Một app target, một test target từ S06. Dependency injection qua initializer tại composition root; không container DI, database, plugin framework hoặc package mới chỉ để chia module.

| Thành phần dự kiến | Trách nhiệm và ranh giới | PLAN / tên đề xuất trong runbook |
|---|---|---|
| LocalTranslatorApp + AppCoordinator | Composition root; sở hữu menu/settings/lifecycle và coordinator; quit hủy tác vụ, tháo shortcut/monitor | Giữ entry hiện có, không dựng lại project |
| AccessibilityPermissionService | Đọc trust, refresh và hướng dẫn mở Settings; chỉ prompt theo hành động người dùng | AccessibilityPermissionManager |
| GlobalShortcutService | Đăng ký ⌥T, conflict, autorepeat, unregister; phát event, không giữ text hay gọi network | GlobalShortcutManager |
| SelectionService | Chụp app nguồn, focused element, text/range và bounds; trả snapshot hoặc lỗi phân loại | SelectedTextProvider + SelectionBoundsProvider; có thể tách file khi triển khai |
| LanguageRouter | Nhận diện local; EN→VI, VI→EN, trả ambiguous/unsupported minh bạch | LanguageDetector |
| TranslationCoordinator | Sở hữu state, task và request ID; route, mở panel, gửi request, nhận delta; quản lý cancellation | TranslationService/Selection Coordinator trong sơ đồ PLAN |
| OllamaClient | Readiness/model list, transport local, stream parser, cancellation; không phụ thuộc SwiftUI/AX | OllamaClient |
| TranslationPromptBuilder | Xây request theo model đã duyệt, nguồn chỉ là dữ liệu; không thực thi output | TranslationRequest / prompt adapter S22 |
| PopupController + PopupPositioner | NSPanel/SwiftUI, placement, Copy/Close/Esc; geometry thuần để test | TranslationPanel, TranslationPopupView, PopupPositioner |
| AppSettings | Chỉ lưu cấu hình như model và lựa chọn Launch at Login; không lưu văn bản | SettingsView, AppSettings |

Giữ LocalTranslatorApp.swift tại vị trí hiện có. ContentView.swift hiện là template, chỉ được thay/loại khi bước shell S06 được duyệt. Thư mục App, Accessibility, Translation, Popup, Shortcut, MenuBar, Settings trong PLAN là tổ chức dự kiến, không phải yêu cầu tạo hàng loạt file rỗng tại S05/S06. Tách interface tại ranh giới cần fake (permission, selection, shortcut, translation, popup); logic routing/geometry/parser dùng value types thuần.

## Luồng và quyền sở hữu dữ liệu

1. Shortcut được nhận khi app nguồn còn focus. Coordinator tạo request ID mới, vô hiệu hóa request cũ rồi hủy task/network cũ.
2. Chụp source PID, thời điểm, vị trí chuột, text/range và bounds nếu có. Không activate utility hoặc mở panel trước snapshot. Nếu app/focus thay đổi trong lúc đọc, từ chối snapshot không nhất quán; không ghép text của app A với bounds của app B.
3. Permission/secure field/empty/unsupported được phân loại rõ. Empty hiện popup nhỏ tự đóng; secure input không đọc hoặc dùng fallback. Unsupported hiện giới hạn tương thích.
4. Router quyết định chiều từ snapshot. Mở panel loading tại bounds hoặc vị trí chuột đã chụp, clamp theo visibleFrame màn tương ứng. Không chờ readiness network trước khi hiện loading.
5. Gửi request tới Ollama ngay sau validation; readiness không được biến thành nhiều lượt health check thừa cho mỗi shortcut. Phân biệt runtime offline và model thiếu, không tự tải model.
6. Parse stream ngoài công việc render; chuyển delta hợp lệ cho MainActor. Chỉ delta của request hiện tại được nối vào output. Gộp cập nhật UI nếu đo đạc chứng minh cần.
7. Copy chỉ do người dùng nhấn; output rỗng thì không báo copy thành công. Close/Esc hủy tác vụ và xóa tham chiếu nội dung; không khôi phục focus mù quáng nếu người dùng đã chuyển app.

Snapshot/request là dữ liệu bất biến, sống trong RAM cho phiên panel hiện tại. Không giữ AX element qua thời gian inference. Retry chủ động dùng snapshot đang hiển thị với ID mới, không đọc lại selection phía sau panel. Khi đóng panel/quit giải phóng source và output; không ghi history, clipboard tự động, URL chứa text, log payload hay telemetry nội dung. Không cam kết secure memory erasure.

## State machine

Coordinator và state UI thuộc MainActor. State gồm phase và context (request ID, snapshot, hướng dịch, output, lỗi có kiểu). Idle không giữ nội dung. Network/NDJSON và AX blocking work không chạy đồng bộ trên UI thread; implementation cần ranh giới isolation tường minh do default MainActor của project. AX messaging có timeout hữu hạn, kiểm chứng ở S10; không chỉ bọc lời gọi blocking bằng Task trên MainActor.

| State | Vào state khi | Chuyển tiếp hợp lệ |
|---|---|---|
| idle | Chưa có yêu cầu hoặc đã dismiss | loading khi trigger |
| loading | ID mới; chụp selection/route/readiness/đợi token đầu | streaming khi có delta; success khi completion hợp lệ có output; error khi lỗi; cancelled khi hủy |
| streaming | Nhận delta đầu tiên, giữ partial output | streaming với delta cùng ID; success khi completion hợp lệ; error khi stream lỗi; cancelled khi hủy |
| success | Server báo hoàn tất rõ ràng, output có nội dung | loading với trigger/retry mới; idle khi đóng |
| error | Permission, selection, runtime, model, transport, malformed stream, input quá dài hoặc hướng chưa xác định | loading khi retry/trigger hợp lệ; idle khi đóng |
| cancelled | Người dùng đóng, quit hoặc request bị thay thế | idle sau cleanup; loading cho request thay thế |

- Phase loading có thể tồn tại trước panel; panel chỉ xuất hiện sau snapshot hoặc sau lỗi selection đã xác định. Mục tiêu <150 ms cần đo cả đoạn AX, không được tự tuyên bố đạt.
- Mọi callback (snapshot, readiness, router, delta, completion, error, timer auto-dismiss) kiểm tra ID trước khi đổi state. Hủy Task không đủ để chặn callback đã xếp hàng.
- Vô hiệu hóa ID trước cancellation; đóng cả stream/network resource. Teardown của request A không được xóa task/state B.
- EOF thiếu completion là error, không success. Completion không có output báo lỗi kết quả rỗng. Partial output khi lỗi được gắn nhãn chưa hoàn tất; cancellation không hiện như crash.
- Có tối đa một request logic hiện hành; mạng cũ phải được cancel, không đợi nó hoàn tất mới nhận trigger mới. Test fake cố tình phát callback muộn để kiểm chứng.

## Local inference và UI

Backend mặc định theo spec: http://localhost:11434. Đề xuất LocalEndpointPolicy chỉ chấp nhận loopback; không tùy biến remote endpoint. Khi triển khai S18 phải kiểm chứng URL/host, redirect, proxy và cache sao cho text không đi ra ngoài máy; không bật ATS arbitrary loads toàn cục. HTTP status và payload đều cần validation. Ollama quản lý model lifecycle; app không load model và không tự tải model nền.

Client/parser tách UI; API cụ thể và prompt được xác minh với Ollama/model thực tế tại S15–S19/S22. Stream parser xử lý byte boundary UTF-8, nhiều frame mỗi chunk, JSON lỗi, server error, premature EOF, cancellation; chỉ nội dung dịch được render, không render thinking/tools. Giới hạn input/context theo model được chốt ở S22, không cắt âm thầm hoặc dựng chunking khi chưa cần.

Panel dùng NSPanel chứa SwiftUI. Khi chỉ hiển thị thì tránh activate app nguồn; keyboard interaction/Esc, Copy, full-screen/Spaces phải được thử thật tại S13/S25. Tự resize trong giới hạn, text dài scroll. Bounds thiếu thì fallback chuột; geometry tính theo layout nhiều màn, không dùng chiều cao một màn cố định. Không thêm click-outside dismiss như requirement bắt buộc vì PLAN chỉ nêu Esc và Close.

Menu gồm trạng thái Ollama/model, Settings, Open Ollama, Quit. S06 dùng trạng thái chưa kiểm tra/fake minh bạch, không giả Connected; kết nối thật chỉ từ S18. Launch at Login là yêu cầu có thật của PLAN, triển khai/kiểm chứng tại S25 sau phê duyệt bước đó; không bật tự động.

## Quyết định cần duyệt hoặc kiểm chứng

| Chủ đề | Recommendation | Đánh đổi / điểm dừng |
|---|---|---|
| Trigger khi bôi đen | MVP shortcut-only ⌥T; không observer/auto-translate | PLAN phần mở đầu có small trigger, nhưng UX chuẩn và MVP liệt kê shortcut. Cần người dùng duyệt cách hiểu; S24 dự kiến N/A, chưa được skip/duyệt trước |
| Fallback | Bounds thiếu → chuột; text AX unsupported → lỗi rõ; không synthetic Cmd+C mặc định | Không bao phủ mọi app. PLAN chưa quy định clipboard fallback; nếu người dùng yêu cầu, chốt opt-in, bảo toàn clipboard, race/secure-input tại S11 trước code |
| Hướng mơ hồ | Không đoán chắc; thông báo không xác định được, chưa gửi request | Ít tiện cho câu ngắn/code/ngôn ngữ khác. Đề xuất tùy chọn EN→VI/VI→EN chỉ cho request hiện tại nếu người dùng duyệt tại S21; không tự thêm preferred-language settings ngoài MVP |
| Model | Chọn exact local tag sau khảo sát máy S15, duyệt trước pull S17 | Chưa có tag trong PLAN; không hứa chất lượng/latency hoặc chọn model cloud |
| Sandbox | Giữ cấu hình hiện có trong S06; kiểm chứng khả năng AX/TCC trước khi coi integration đạt ở S08/S10 | Tại S05, ENABLE_APP_SANDBOX=YES là fact cấu hình, không phải bằng chứng tương thích. Đã giải quyết ở S07: sandbox chặn prompt Accessibility nên ENABLE_APP_SANDBOX=NO (người dùng duyệt). Nếu cần đổi sandbox/entitlement, trình thay đổi và chờ duyệt trước áp dụng; không đợi tới release mới phát hiện |
| Phân phối | Ưu tiên chạy local trước; chưa chọn App Store hay public release | Local ad-hoc chưa phải artifact phân phối. Chốt route tại S28, signing/notarization riêng tại S30 nếu cần; không tự chọn Team/upload |

Những điểm này không cản dựng shell với fake ở S06, nhưng cản phần implementation phụ thuộc nếu chưa có quyết định. S05 chỉ ghi đề xuất, không tự cấp quyền hoặc tuyên bố hạn chế nền tảng đã được xác minh bằng thử nghiệm.

## Kiểm chứng thiết kế và phạm vi S06 kế tiếp

Đã review tĩnh các tình huống: shortcut A→B liên tiếp, đóng panel trước token đầu, lỗi giữa stream, callback cũ đến sau retry, thiếu bounds, không có selection. Mỗi trường hợp có owner, state và cleanup rõ như trên; chưa phải runtime test.

Phạm vi S06 đã được duyệt: chỉ composition root/menu/settings/quit, interfaces và fake cần thiết, state transitions cùng test target/shared scheme. Không AX thật, đăng ký shortcut thật, network, panel dịch, launch-at-login registration hoặc logic dịch ở S06. Mọi bước sau tiếp tục giữ STOP riêng theo runbook.

## Ghi nhận S06

Shell đã dùng AppDelegate/AppCoordinator, MenuBarExtra, Settings và protocol readiness với dependency inert; state machine đồng bộ có test. Chưa triển khai các services tương lai trong bảng thiết kế. UI acceptance S06 vẫn chờ kiểm tra tay; xem PROGRESS.md. Các decision gates model, ambiguous-language UX, sandbox/AX và release route vẫn giữ nguyên.

## Ghi nhận S07

AccessibilityPermissionService triển khai hàng "AccessibilityPermissionService" trong bảng trên: đọc trust qua AXIsProcessTrusted, chỉ prompt khi người dùng bấm Request Access (tối đa một lần mỗi lần chạy), mở Privacy & Security › Accessibility. Trạng thái denied và chưa cấp gộp là notGranted vì macOS không phân biệt. Chưa đọc selected text; kiểm chứng TCC thật ở S08.

Quyết định sandbox (S07, người dùng duyệt): App Sandbox chặn hộp thoại và đăng ký quyền Accessibility (bản chẩn đoán không sandbox hiện hộp thoại, bản sandbox thì không). Target app đặt ENABLE_APP_SANDBOX = NO cho Debug và Release. Hệ quả: không phân phối qua Mac App Store; route phát hành chốt ở S28. Việc đọc selected text qua AX từ app khác vẫn cần kiểm chứng ở S10.

## Ghi nhận S09–S10

- S09: GlobalShortcutService dùng Carbon RegisterEventHotKey (exclusive) cho ⌥T; không cần Input Monitoring; một lần nhấn = một trigger.
- S10: SelectedTextService chụp SelectionSnapshot bất biến ngay khi trigger, đọc AX trên queue riêng với messaging timeout 0,25 s, kiểm tra secure input trước khi đọc text, từ chối khi focus/app đổi trong lúc đọc. Snapshot chỉ ở RAM; UI debug tạm chỉ trong bản Debug.

Ghi nhận S12: anchor lấy từ `kAXBoundsForRangeParameterizedAttribute`, đổi AX→AppKit chỉ theo frame màn chính, chọn màn theo diện tích giao lớn nhất và cắt theo visibleFrame; thiếu/không hợp lệ/ngoài màn → vị trí chuột lúc trigger, clamp vào visibleFrame. Popup (S13/S14) đặt theo `SelectionAnchor.rect` và phải nằm trong `visibleFrame`.

Ghi nhận S13: popup là NSPanel `.nonactivatingPanel` hiển thị bằng `orderFrontRegardless` (không lấy key, không activate app); Esc là Carbon hot key chỉ đăng ký khi popup đang hiện (mỗi registrar có hot key ID riêng); fallback khi Esc bị chiếm: panel nhận key để xử lý `cancelOperation`. Không đóng khi click ra ngoài (PLAN chỉ nêu Esc/Close). Copy chỉ khi bấm nút.

Ghi nhận S14: `TranslationCoordinator` là owner của luồng ⌥T và `TranslationStateMachine`; `AppCoordinator` chỉ còn composition. Mỗi trigger hủy capture/request/notice trước, request ID chặn kết quả cũ; Esc/× hủy stream và xóa output. `TranslationProviding` là seam cho Ollama client (S18–S20); hiện dùng `PlaceholderTranslationService` phát lại chính văn bản đã chọn, không network. UI debug tạm S10–S13 đã gỡ.

Ghi nhận S18: `OllamaClient` (transport seam, chỉ loopback, chặn redirect, kiểm tra URL request/response) tách khỏi `TranslationModelConfiguration` (tag + prompt theo model); `OllamaReadinessService` là nguồn trạng thái runtime/model cho menu và Settings. Luồng ⌥T vẫn dùng placeholder đến S20.

Ghi nhận S20: `OllamaTranslationService` (TranslationProviding) dùng chung `OllamaReadinessService` với menu/Settings; coordinator gộp render 40 ms, lỗi giữ partial + thông báo PLAN §14; hủy Task lan tới URLSession và Ollama (server log `cancel task`).
