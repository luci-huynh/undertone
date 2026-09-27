# CODEX_RUNBOOK — Local AI Translator cho macOS

Tài liệu điều hành phát triển theo từng bước, có xác nhận bắt buộc. **PLAN.md là product spec; runbook này quy định cách thực hiện, không thay thế spec.**

Runbook chưa được đối chiếu với bản PLAN.md thực tế. Tên file Swift bên dưới là cấu trúc đề xuất; khi repo đã có cấu trúc hợp lý, dùng cấu trúc hiện có và ghi rõ mapping. Không tự thêm tính năng chỉ vì có tên trong ví dụ.

## 1. Operator protocol — đọc trước mọi bước

1. Chỉ thực hiện **một bước có ID** trong mỗi lượt được người dùng cho phép. Bắt đầu bằng S01. Không chạy toàn bộ tài liệu.
2. Sau **mọi bước**, kể cả chỉ mở Xcode, kiểm tra repo, bước bị skip, bước thất bại hoặc kiểm tra thành công: **STOP và hỏi xác nhận rõ ràng**. Không tự bắt đầu bước tiếp theo. Full permissions chỉ cho phép thao tác trong bước đang được giao; không thay thế xác nhận chuyển bước.
3. Không gộp hai ID vào một lượt, không chuẩn bị ngầm code của bước sau, không giao agent khác làm trước. Các thao tác triển khai và kiểm tra liệt kê trong một ID thuộc một đơn vị công việc. Nếu phát hiện cần chia ID thành sub-phase, đặt ID như S08a/S08b **trước khi làm**, thực hiện duy nhất sub-phase đầu và xin xác nhận trước sub-phase sau.
4. Xác nhận hợp lệ: người dùng yêu cầu rõ bước cụ thể, ví dụ `Xác nhận S08, làm S09`. `Tiếp tục` chỉ có hiệu lực cho đúng một bước kế tiếp khi trạng thái không mơ hồ. Im lặng, thời gian chờ, quyền hệ thống, build pass và lời xác nhận cũ không phải xác nhận mới.
5. Trước mỗi bước, đọc PLAN.md, AGENTS.md áp dụng và trạng thái gần nhất. PLAN.md quyết định feature, milestone, minimum macOS, model, UX và tiêu chí sản phẩm. Nếu thiếu PLAN.md: báo thiếu, dừng; không dựng spec từ hội thoại. Nếu mâu thuẫn ảnh hưởng đáng kể kết quả: mô tả cụ thể và chờ người dùng quyết định.
6. Không sửa PLAN.md để hợp thức hóa implementation. Khi spec chưa rõ, dùng mặc định đơn giản cho chi tiết ít ảnh hưởng, ghi nhận giả định. Quyết định lớn như clipboard fallback, tự động dịch khi bôi đen, endpoint ngoài máy, phân phối App Store phải được chốt trước khi triển khai phần đó.
7. Có thể sửa lỗi trực tiếp thuộc bước đang chạy rồi kiểm tra lại trong cùng lượt. Nếu cần đổi scope, quyền, dependency hoặc kiến trúc đã chốt: dừng tại blocker. Không chuyển bước khi còn lỗi bắt buộc.
8. Không xóa/ghi đè thay đổi sẵn có. Trước sửa, đọc diff và ghi danh sách file dự kiến. Không `git reset --hard`, `git clean -fd`, force push hoặc reset quyền toàn hệ thống. Không commit/push/publish tự động. Chỉ tạo checkpoint commit khi người dùng cho phép riêng; chỉ stage file thuộc bước đó.
9. Quyền đầy đủ vẫn không cho phép vượt cơ chế bảo vệ macOS. Người dùng tự xác nhận hộp thoại quyền, đăng nhập Apple ID, nhập mật khẩu. Nếu công cụ UI không khả dụng, đưa thao tác tay chính xác và chờ kết quả; không báo đã click khi chưa thực hiện.
10. Inference chỉ local qua Ollama. Không gửi văn bản chọn lên cloud, telemetry hoặc log. Không tự bật fallback cloud. Tải app/model có thể cần Internet; sau setup phải thử offline. Không gọi dịch trên nội dung thật chỉ để debug.
11. Không báo manual check là PASS nếu chưa quan sát hoặc chưa được người dùng xác nhận. Phân biệt `PASS`, `FAIL`, `BLOCKED`, `NOT RUN`. Một bước phụ thuộc kiểm tra tay chưa làm phải giữ trạng thái chờ.
12. Kết thúc lượt bằng báo cáo và câu hỏi mẫu bên dưới rồi **kết thúc response**. Không dùng vòng lặp chờ rồi tự tiếp tục.

### Prompt khởi động — paste một lần

```text
Đọc CODEX_RUNBOOK.md và tuân thủ Operator protocol. PLAN.md là product spec.
Chỉ thực hiện S01 trong lượt này. Không làm S02 hoặc bất kỳ bước nào sau đó.
Sau S01, báo kết quả và STOP để chờ tôi xác nhận rõ ràng.
Full permissions không phải quyền tự động chuyển bước.
```

### Báo cáo bắt buộc cuối mỗi bước

```text
Bước/sub-phase: Sxx — tên
Kết quả: PASS / FAIL / BLOCKED / NOT RUN
Đã thay đổi: file và hành vi thực tế
Đã kiểm tra: lệnh, exit code, kết quả; manual check nào còn chờ
Giả định / giới hạn / lỗi còn lại:
Rollback: cách hoàn nguyên chỉ phần thay đổi của bước
Bước đề xuất tiếp theo: Syy — tên (CHƯA THỰC HIỆN)
STOP / WAIT FOR USER CONFIRMATION
Bạn xác nhận hoàn tất Sxx và cho phép tôi thực hiện riêng Syy không?
```

Nếu FAIL/BLOCKED: hỏi cho phép sửa hoặc cung cấp thông tin để hoàn tất **chính Sxx**, không hỏi chuyển sang Syy. Ghi trạng thái trong `docs/PROGRESS.md` từ S04 trở đi, không đánh dấu bước tương lai đã được duyệt.

## 2. Quy ước kiểm tra và rollback

Tất cả lệnh chạy tại repo root. Không paste biến/path giả vào shell. S04 phải phát hiện tên project, shared scheme, target và đường dẫn thực tế rồi điền vào `docs/BUILD.md`. Không giả định tên scheme chỉ từ tên thư mục.

Các ký hiệu dưới đây là nhóm lệnh tham chiếu, **không phải executable alias**:

**I — kiểm tra thay đổi** (chỉ sau khi xác nhận đây là repo đúng):

```sh
git status --short
git diff --check
git diff --stat
```

**B — build Debug** (mẫu, thay project/scheme theo S04):

```sh
xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

**T — unit tests**, sau khi đã tạo test target/shared scheme ở S06:

```sh
xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
```

Nếu dự án dùng workspace, đổi `-project ...` thành `-workspace ...` xuyên suốt. Không tắt code signing để che lỗi: build phục vụ kiểm tra Accessibility phải chạy đúng app identity. Build không thay thế runtime test hoặc kiểm tra TCC.

**R — build Release**:

```sh
xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

Rollback mặc định: xem diff, hoàn nguyên đúng các hunk do bước hiện tại tạo; giữ thay đổi của người dùng. Nếu có checkpoint được duyệt, đề xuất revert đúng commit. Không tự xóa model, gỡ Ollama, đổi global Xcode path hoặc thu hồi quyền chỉ để rollback code. File build sinh ra đặt trong `.build/`, loại khỏi Git.

## 3. Các bước thực hiện

### S01 — Đọc spec và mở Xcode

**Mục tiêu:** Xác nhận đầu vào, mở Xcode; chưa tạo project.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S01 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Tìm PLAN.md trong thư mục người dùng cung cấp, đọc đầy đủ và tóm tắt các ràng buộc bắt buộc. Nếu không có thì dừng yêu cầu đường dẫn. Kiểm tra Xcode đã cài rồi mở Xcode đến màn hình chào hoặc cửa sổ hiện có. Không tạo project, repo hoặc source.
Kiểm tra theo mục S01, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Không sửa source; báo đường dẫn PLAN.md, Xcode version và project đã tồn tại hay chưa.

**Lệnh kiểm tra/build:** `xcodebuild -version`; `xcode-select -p`; `open -a Xcode` sau khi xác nhận app tồn tại. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Người dùng thấy Xcode mở; xác nhận đúng PLAN.md.

**Success criteria:** Spec đọc được và Xcode mở thành công.

**Lỗi thường gặp / lưu ý:** Chỉ có Command Line Tools không đồng nghĩa đã cài Xcode. Nếu thiếu Xcode/license/first-launch components, ghi blocker và xin thực hiện sub-phase setup riêng. Không tự cài công cụ lớn.

**Rollback:** Đóng cửa sổ vừa mở nếu cần; không đụng project hiện có.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S02**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S02 — Chốt cấu hình project

**Mục tiêu:** Chốt đường dẫn và thông số trước khi wizard tạo file.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S02 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Đối chiếu PLAN.md; đề xuất đúng một cấu hình project: native macOS App, Swift, SwiftUI kết hợp AppKit, product name, bundle ID, minimum macOS, repo root, thư mục lưu. Kiểm tra project trùng tên. Không tạo project. Không tự suy đoán Team Apple Developer.
Kiểm tra theo mục S02, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Bảng cấu hình trong báo cáo; chưa có source mới.

**Lệnh kiểm tra/build:** `pwd`; `ls -la`; `xcodebuild -version` nếu S01 chưa xác định. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Xác nhận vị trí lưu, tên app, bundle ID; chọn Team có sẵn hoặc để chưa cấu hình theo khả năng build local.

**Success criteria:** Có cấu hình cụ thể đã sẵn sàng để người dùng duyệt.

**Lỗi thường gặp / lưu ý:** Tránh thư mục lồng LocalTranslator/LocalTranslator ngoài ý muốn. Nếu project có sẵn, S03 sẽ mở/kiểm tra nó, không tạo đè.

**Rollback:** Không có thay đổi cần rollback.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S03**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S03 — Tạo project bằng Xcode

**Mục tiêu:** Có shell app macOS tối thiểu.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S03 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Dùng UI Xcode tạo project theo cấu hình S02: New Project > macOS > App, SwiftUI, Swift; không thêm persistence nếu PLAN không yêu cầu. Chưa bật tùy chọn tạo Git repo để S04 xử lý. Nếu đã có project phù hợp, mở và kiểm tra thay vì tạo lại. Không thêm feature.
Kiểm tra theo mục S03, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Project .xcodeproj, app entry và view template; asset catalog do Xcode sinh.

**Lệnh kiểm tra/build:** `xcodebuild -list -project LocalTranslator.xcodeproj` với path thực tế; build bằng Xcode Product > Build. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Run app từ Xcode; thấy cửa sổ template, không crash.

**Success criteria:** Project mở và shell build/run được; ghi build error chính xác nếu chưa được.

**Lỗi thường gặp / lưu ý:** UI template thay đổi theo Xcode. Signing, SDK hoặc license lỗi phải giải quyết trong scope bootstrap; không chọn Team ngẫu nhiên.

**Rollback:** Chỉ xóa file mới tạo sau khi người dùng đồng ý và đã xác nhận không chứa dữ liệu có sẵn.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S04**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S04 — Kiểm tra hoặc khởi tạo repo

**Mục tiêu:** Thiết lập baseline và lệnh build tái lập.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S04 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Kiểm tra git root trước khi git init; tránh vô tình dùng repo cha. Nếu chưa có repo đúng phạm vi thì khởi tạo tại root đã chốt. Đặt PLAN.md và runbook ở root bằng cách sao chép file gốc, không viết lại spec. Giữ AGENTS.md hiện có, bổ sung protocol STOP nếu không xung đột. Ghi build command thật và baseline status.
Kiểm tra theo mục S04, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `.gitignore`, `docs/BUILD.md`, `docs/PROGRESS.md`, AGENTS.md cập nhật có kiểm soát; PLAN.md giữ nguyên nội dung.

**Lệnh kiểm tra/build:** `git rev-parse --show-toplevel` (thất bại là bình thường khi chưa có Git); `git init` chỉ nếu cần; `xcodebuild -list -project <path-thực>`; I và B. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Xem diff, xác nhận repo root và không đưa user data/DerivedData vào Git.

**Success criteria:** Đúng repo, shared scheme dùng được, lệnh B đã chạy thành công và có ghi nhận baseline.

**Lỗi thường gặp / lưu ý:** Không tạo repo lồng khi không chủ ý; scheme không shared sẽ khó tái lập. Không commit thay đổi không thuộc task.

**Rollback:** Hoàn nguyên file cấu hình theo diff; không xóa .git của repo có sẵn.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S05**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S05 — Chốt kiến trúc

**Mục tiêu:** Thiết kế tối thiểu, chưa triển khai các feature.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S05 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Map từng yêu cầu PLAN.md sang bước trong runbook; ghi feature còn thiếu hoặc bước không áp dụng. Đề xuất services: Accessibility, Shortcut, Selection, Popup, LanguageRouter, OllamaClient và TranslationCoordinator. Chốt state machine idle/loading/streaming/success/error/cancelled; main actor cho UI, cancellation và request identity. Ghi quyết định sandbox/distribution cần kiểm chứng, không mặc định App Store.
Kiểm tra theo mục S05, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/ARCHITECTURE.md`, `docs/SPEC-MAP.md`; chưa code dịch.

**Lệnh kiểm tra/build:** I; B chỉ khi thay project/source. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Review flow: shortcut → snapshot selection → route → panel → Ollama → stream. Không chiếm focus trước khi đọc selection.

**Success criteria:** Mọi yêu cầu PLAN có mapping; quyết định lớn chưa rõ được nêu ra trước code.

**Lỗi thường gặp / lưu ý:** Không hứa hoạt động mọi app; AX phụ thuộc app nguồn. Không thêm database/plugin framework cho MVP.

**Rollback:** Hoàn nguyên tài liệu của bước theo diff.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S06**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S06 — Dựng app shell và test seam

**Mục tiêu:** Có composition root, menu bar và test target.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S06 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Dựng shell theo S05 với dependency injection nhẹ, menu bar/settings/quit theo PLAN; tạo protocol và fake service, chưa implement AX/network. Tạo unit test target và shared scheme; test state transition có ý nghĩa.
Kiểm tra theo mục S06, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** App entry, AppCoordinator, service protocols, test target, shared scheme.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Mở/quit từ menu bar; không có cửa sổ thừa nếu spec yêu cầu utility.

**Success criteria:** Shell chạy, test target thực sự chạy và không gọi network.

**Lỗi thường gặp / lưu ý:** Test scheme có 0 tests không được tính PASS. Giữ cấu trúc nhỏ, không dựng framework riêng.

**Rollback:** Hoàn nguyên shell và project hunk; giữ template baseline.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S07**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S07 — Trạng thái quyền Accessibility

**Mục tiêu:** Đọc trạng thái và hướng dẫn cấp quyền.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S07 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement AX permission service với AXIsProcessTrusted/AXIsProcessTrustedWithOptions theo SDK. Chỉ prompt khi người dùng chủ động yêu cầu. Có trạng thái denied/not-granted và nút mở System Settings. Chưa lấy selected text.
Kiểm tra theo mục S07, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** AccessibilityPermissionService.swift; onboarding/settings permission view.

**Lệnh kiểm tra/build:** I, B; T cho mapping trạng thái bằng mock. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Mở app khi chưa được cấp quyền; xem lời giải thích rõ và đường dẫn Privacy & Security > Accessibility.

**Success criteria:** Không crash, không lặp prompt; app không giả báo đã có quyền.

**Lỗi thường gặp / lưu ý:** Quyền của Codex không phải quyền app đang build. Không yêu cầu Screen Recording/Input Monitoring nếu chưa có nhu cầu thực tế.

**Rollback:** Hoàn nguyên service/view; không reset TCC.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S08**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S08 — Cấp và kiểm chứng quyền thực tế

**Mục tiêu:** Xác nhận TCC cho đúng app đang chạy.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S08 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Chạy app từ đường dẫn ổn định; hướng dẫn người dùng bật Accessibility cho đúng app. Chờ thao tác người dùng, sau đó refresh trust state, relaunch nếu cần. Thử trường hợp revoke và re-enable có người dùng tham gia. Không tự click vượt hộp thoại bảo mật.
Kiểm tra theo mục S08, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/PERMISSIONS.md`; chỉ sửa bug refresh thuộc quyền nếu cần.

**Lệnh kiểm tra/build:** B nếu sửa code; ghi executable path/bundle ID trong báo cáo. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Người dùng bật quyền; app chuyển trạng thái đúng; sau thu hồi app báo thiếu quyền.

**Success criteria:** Có bằng chứng trạng thái thật; chưa cấp được thì BLOCKED.

**Lỗi thường gặp / lưu ý:** Build đổi signing/path có thể ảnh hưởng TCC; kiểm tra đúng binary trước khi đề xuất reset riêng bundle. Không chạy tccutil reset toàn bộ.

**Rollback:** Người dùng có thể tắt quyền cho đúng app trong Settings.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S09**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S09 — Global shortcut

**Mục tiêu:** Gọi được một action khi app ở nền.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S09 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement đăng ký global shortcut phù hợp SDK/minimum OS và PLAN. Chọn API hệ thống hoặc dependency nhỏ chỉ khi cần, ghi lý do. Xử lý conflict, unregister và autorepeat. Action hiện chỉ cập nhật trạng thái nội bộ, không dịch.
Kiểm tra theo mục S09, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** GlobalShortcutService.swift; binding cấu hình nếu PLAN yêu cầu.

**Lệnh kiểm tra/build:** I, B; T cho lifecycle/conflict qua mock. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Trong TextEdit và browser, nhấn shortcut; thử giữ phím, quit/relaunch.

**Success criteria:** Một thao tác tạo một event; app ở nền vẫn nhận; conflict có thông báo.

**Lỗi thường gặp / lưu ý:** NSEvent local monitor đơn thuần không phải global shortcut. Không lấy focus app nguồn ở thời điểm trigger.

**Rollback:** Unregister handler khi teardown; hoàn nguyên code hoặc cấu hình shortcut.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S10**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S10 — Lấy selected text qua AX

**Mục tiêu:** Chụp selection trước khi popup lấy focus.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S10 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement đọc frontmost app/focused AX element, selected text và selected range; giữ snapshot source PID, text, range, timestamp. Xử lý AX errors, empty selection, unsupported và secure fields; không log text. Không dùng clipboard fallback ở bước này.
Kiểm tra theo mục S10, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** SelectedTextService.swift, SelectionSnapshot.swift; unit tests cho lỗi/empty text.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Chọn đoạn EN/VI ở TextEdit và browser; trigger; kiểm chứng nội dung bằng debug UI tạm không lưu log. Thử không chọn gì và trường mật khẩu.

**Success criteria:** Lấy đúng đoạn chọn, không toàn tài liệu; unsupported có kết quả rõ; không đọc secure input.

**Lỗi thường gặp / lưu ý:** Một số Electron/PDF/custom views không expose selection. AX call có thể chậm: tránh treo UI, cấu hình messaging timeout phù hợp.

**Rollback:** Bỏ debug UI sau kiểm chứng; hoàn nguyên service; không thay đổi clipboard.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S11**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S11 — Fallback cho app không hỗ trợ

**Mục tiêu:** Xử lý giới hạn tương thích theo spec.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S11 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Đọc yêu cầu fallback trong PLAN. Nếu không yêu cầu, ghi unsupported UX và đánh dấu bước không áp dụng, vẫn STOP. Nếu yêu cầu clipboard fallback, chỉ triển khai sau khi hành vi đã được duyệt: opt-in, chỉ chạy từ trigger chủ động, bảo vệ clipboard nhiều loại dữ liệu và changeCount, không ghi đè khi user/app khác vừa đổi clipboard, không dùng secure input.
Kiểm tra theo mục S11, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Fallback adapter và tests nếu áp dụng; `docs/COMPATIBILITY.md` ghi giới hạn.

**Lệnh kiểm tra/build:** I, B, T nếu code đổi; nếu N/A chỉ I. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử clipboard chứa text/image, người dùng copy mới trong lúc fallback, timeout, app từ chối copy.

**Success criteria:** Fallback không âm thầm làm mất clipboard; nếu không bảo đảm được thì tắt và báo giới hạn.

**Lỗi thường gặp / lưu ý:** Synthetic Cmd+C có thể thất bại hoặc cần quyền khác. Không giả định restore text là restore toàn clipboard; không hứa hỗ trợ mọi app.

**Rollback:** Tắt opt-in fallback trước, hoàn nguyên adapter; không cố restore clipboard cũ sau thao tác người dùng mới.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S12**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S12 — Lấy selection bounds

**Mục tiêu:** Có anchor đúng hoặc fallback vị trí rõ ràng.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S12 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Dùng selected range và AX bounds-for-range nếu supported. Chuẩn hóa AX/Quartz sang AppKit coordinates dựa trên screen layout; không dùng một screen-height cố định cho mọi màn hình. Nếu thiếu bounds, dùng vị trí chuột được chụp tại trigger và clamp vào visibleFrame. Xử lý multi-line/zero rect/offscreen.
Kiểm tra theo mục S12, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** SelectionBoundsService.swift, ScreenGeometry.swift; geometry tests.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử màn chính/phụ ở trái/phải/trên, Retina, selection nhiều dòng và sát mép màn.

**Success criteria:** Anchor nằm trên đúng màn hình; thiếu bounds không ngăn dịch; popup tương lai không ra ngoài vùng dùng được.

**Lỗi thường gặp / lưu ý:** Không trộn point với pixel; AX bounds có thể là hợp rect hoặc không hỗ trợ.

**Rollback:** Hoàn nguyên geometry; giữ text snapshot hoạt động.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S13**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S13 — Floating NSPanel

**Mục tiêu:** Popup hoạt động với nội dung giả.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S13 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Tạo NSPanel chứa SwiftUI bằng NSHostingView; cấu hình floating/nonactivating phù hợp UX, tránh steal focus trước snapshot. Hiển thị text giả; đóng Escape/outside click theo PLAN, quản lý event monitors và lifecycle. Không gọi Ollama.
Kiểm tra theo mục S13, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** TranslationPanelController.swift, TranslationPopupView.swift.

**Lệnh kiểm tra/build:** I, B; T cho logic placement/state tách khỏi UI. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử focus, copy text giả, Escape, click ngoài, nhiều lần mở/đóng, Spaces/full-screen và nhiều màn hình.

**Success criteria:** Panel đúng vị trí, không leak monitor, không mất selection nguồn khi mở.

**Lỗi thường gặp / lưu ý:** Nonactivating panel vẫn cần thiết kế key handling cho tương tác; full-screen behavior phải kiểm tra thực tế.

**Rollback:** Đóng panel, tháo monitor rồi hoàn nguyên controller/view.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S14**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S14 — Luồng selection → popup

**Mục tiêu:** Nối shortcut, snapshot và panel bằng dịch giả.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S14 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Nối S09–S13 qua coordinator. Dùng fake translation; mỗi trigger có request ID, selection snapshot bất biến, cancel request trước, dismiss cleanup. Không network.
Kiểm tra theo mục S14, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** TranslationCoordinator.swift; integration tests với fake services.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Chọn A rồi chọn B nhanh; mở/đóng giữa loading giả; đổi app nguồn.

**Success criteria:** Popup chỉ hiện selection/request mới nhất; không có kết quả cũ ghi đè.

**Lỗi thường gặp / lưu ý:** Đừng đọc selection lại sau panel đã mở; không giữ AX element lâu không cần thiết.

**Rollback:** Quay về panel text giả độc lập; hoàn nguyên coordinator hunk.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S15**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S15 — Kiểm tra môi trường Ollama

**Mục tiêu:** Biết máy đang có gì trước cài đặt.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S15 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Kiểm tra Ollama hiện có, process/endpoint local, kiến trúc máy, RAM, dung lượng trống và model tag PLAN yêu cầu. Chỉ đọc, không cài hoặc pull model. Ghi lựa chọn model còn thiếu; không lấy recommendation cũ trong chat làm spec.
Kiểm tra theo mục S15, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/OLLAMA.md` phần môi trường và model dự kiến.

**Lệnh kiểm tra/build:** `command -v ollama`; `ollama --version` nếu có; `uname -m`; `sysctl -n hw.memsize`; `df -h .`; `curl --fail --show-error --max-time 5 http://127.0.0.1:11434/api/tags`. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Xác nhận model phù hợp dung lượng/RAM và là model chạy local; xem runtime có đang dùng cho công việc khác không.

**Success criteria:** Biết rõ installed/running/model-present, hoặc ghi thiếu từng phần.

**Lỗi thường gặp / lưu ý:** Không coi endpoint lỗi là cần cài lại. Chưa benchmark thì không hứa latency.

**Rollback:** Không có thay đổi hệ thống cần rollback.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S16**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S16 — Cài hoặc khởi chạy Ollama

**Mục tiêu:** Runtime local sẵn sàng.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S16 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Dựa S15, dùng bản Ollama chính thức hoặc bản đang cài. Nếu đã chạy, chỉ kiểm tra. Không chạy thêm daemon trùng, không mở port ra LAN; không pull model trong bước này. Nếu installer cần thao tác người dùng, chờ.
Kiểm tra theo mục S16, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/OLLAMA.md` cập nhật cách cài/start/version; không sửa feature app.

**Lệnh kiểm tra/build:** `ollama --version`; `curl --fail --show-error --max-time 5 http://127.0.0.1:11434/api/tags`. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Endpoint trả JSON, không bind public interface ngoài nhu cầu; xác định app/process khởi động.

**Success criteria:** Runtime local hoạt động hoặc blocker được ghi rõ.

**Lỗi thường gặp / lưu ý:** Port bị chiếm: xác định process, không kill tùy tiện. Không thay package manager hay cấu hình startup toàn máy ngoài scope.

**Rollback:** Dừng đúng process do bước này khởi động nếu cần; không uninstall bản có sẵn.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S17**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S17 — Tải và kiểm tra model

**Mục tiêu:** Model cụ thể sẵn sàng offline.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S17 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Dùng đúng model tag PLAN hoặc tag đã được người dùng duyệt ở S15. Kiểm tra tài liệu/model card về cách prompt dịch, EN/VI, license và dung lượng; pull nếu thiếu. Chỉ dùng câu thử tổng hợp. Không thay model âm thầm khi hết RAM.
Kiểm tra theo mục S17, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/OLLAMA.md` ghi exact tag/digest nếu có, yêu cầu prompt và kết quả smoke test.

**Lệnh kiểm tra/build:** `ollama list`; `ollama pull <tag-đã-duyệt>` chỉ khi thiếu; `ollama show <tag-đã-duyệt>`; `ollama run <tag-đã-duyệt>` để thử câu tổng hợp. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử một câu EN→VI và VI→EN; ngắt Internet rồi thử khi model đã tải xong.

**Success criteria:** Model load được, hai chiều có kết quả hợp lý, inference không cần cloud.

**Lỗi thường gặp / lưu ý:** Tag cloud không đạt yêu cầu local. Model chuyên dịch có thể cần prompt template riêng; không áp một system prompt cho mọi model.

**Rollback:** Không xóa model đã có. Nếu muốn thu hồi dung lượng model mới tải, yêu cầu người dùng duyệt rõ tag cần xóa.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S18**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S18 — Ollama client và readiness

**Mục tiêu:** App nhận biết runtime/model, gọi dịch không streaming.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S18 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement URLSession client, readiness/model availability và request non-streaming bằng câu test tổng hợp. Cấu hình model tách khỏi client. Chỉ chấp nhận loopback endpoint; kiểm tra redirect và ngăn đi host ngoài máy. Không mở ATS arbitrary loads toàn cục; nếu vướng transport/sandbox phải chẩn đoán cấu hình tối thiểu.
Kiểm tra theo mục S18, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** OllamaClient.swift, OllamaModels.swift, LocalEndpointPolicy.swift; mock transport tests.

**Lệnh kiểm tra/build:** I, B, T; gọi /api/tags bằng curl như S15 để so sánh readiness. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Tắt runtime, chọn model không tồn tại, khởi động lại, thử endpoint không-local.

**Success criteria:** Phân biệt runtime unavailable/model missing; request local thành công và endpoint ngoài máy bị chặn.

**Lỗi thường gặp / lưu ý:** HTTP 200 chưa đủ để kết luận payload hợp lệ. Không thêm OpenAI key/cloud SDK.

**Rollback:** Hoàn nguyên client/config; giữ runtime/model đã cài.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S19**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S19 — Streaming parser

**Mục tiêu:** Đọc stream đúng dưới nhiều kiểu chunk.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S19 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement stream Ollama cho API đã chọn; nếu /api/chat thì đọc message.content và done. Parse NDJSON theo dòng, không giả định network chunk là JSON hoàn chỉnh; hỗ trợ UTF-8 bị chia, dòng rỗng, error frame, EOF thiếu completion và cancellation. Không nối UI thật ở bước này.
Kiểm tra theo mục S19, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** OllamaStreamParser.swift; fixture và parser tests.

**Lệnh kiểm tra/build:** I, B, T với fixture chia tại nhiều byte boundary, nhiều JSON trên một chunk, malformed JSON và EOF. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Smoke stream câu tổng hợp; kiểm tra thấy delta tăng dần và kết thúc rõ.

**Success criteria:** Không mất dấu tiếng Việt/nhân đôi token; premature EOF không bị báo success.

**Lỗi thường gặp / lưu ý:** Thinking/tool payload không phải bản dịch; không render nhầm các trường phụ.

**Rollback:** Quay về client non-streaming, giữ fixture để tái hiện lỗi.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S20**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S20 — Streaming lên popup

**Mục tiêu:** Thay fake translation bằng client thật.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S20 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Nối stream vào coordinator; cập nhật UI trên main actor, gộp cập nhật khi cần, cancel Task và network khi đóng hoặc trigger mới. Chặn delta cũ bằng request ID. Hiện loading trước token đầu và partial/error sau ngắt.
Kiểm tra theo mục S20, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Coordinator, popup state/view cập nhật; lifecycle tests.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Dịch A rồi B nhanh, đóng giữa stream, tắt Ollama giữa stream, stream đoạn dài.

**Success criteria:** UI không đứng; chỉ request mới ghi kết quả; đóng panel không còn tác vụ lơ lửng.

**Lỗi thường gặp / lưu ý:** Cancel UI Task mà network vẫn đọc là chưa đủ; kiểm tra teardown thực tế.

**Rollback:** Quay về fake service qua composition root; không xóa client đã kiểm chứng.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S21**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S21 — Nhận diện EN ↔ VI

**Mục tiêu:** Routing có thể sửa khi text mơ hồ.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S21 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Implement LanguageRouter bằng cơ chế local phù hợp, ví dụ NLLanguageRecognizer, với confidence policy có test. EN→VI, VI→EN; câu ngắn, không dấu, trộn ngôn ngữ, code/URL và ngôn ngữ khác không được đoán chắc. Hiện hướng dịch; manual override theo PLAN; lưu override chỉ theo phạm vi spec.
Kiểm tra theo mục S21, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** LanguageRouter.swift, direction UI, bilingual fixtures/tests.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử câu EN, VI có dấu/không dấu, “OK”, câu trộn và tiếng khác; đổi hướng khi chưa/đang stream.

**Success criteria:** Các case rõ route đúng; case mơ hồ có cách xử lý minh bạch; đổi hướng không nhận delta cũ.

**Lỗi thường gặp / lưu ý:** Không coi cứ có dấu là VI hoặc ASCII là EN. Nếu PLAN không định nghĩa ambiguous UX, trình phương án đơn giản rồi dừng trước phần phụ thuộc.

**Rollback:** Hoàn nguyên router, dùng hướng test cố định chỉ ở debug.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S22**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S22 — Chất lượng prompt dịch

**Mục tiêu:** Bản dịch bám nội dung và đúng model.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S22 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Tách prompt adapter theo model đã chọn; nguồn là dữ liệu cần dịch, không phải lệnh của app. Giữ tên riêng/số/format cần thiết theo PLAN, không chèn giải thích hoặc reasoning. Xử lý giới hạn context trước gửi, không cắt âm thầm. Không thêm chunking phức tạp nếu spec chưa yêu cầu.
Kiểm tra theo mục S22, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** TranslationPromptBuilder.swift; `Tests/Fixtures/TranslationCases` với text tổng hợp.

**Lệnh kiểm tra/build:** I, B, T; chạy bộ câu EN/VI qua model local, ghi model/version và đánh giá thủ công. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thử số tiền/ngày, phủ định, thuật ngữ, đoạn chứa “ignore previous instructions” và văn bản nhiều dòng.

**Success criteria:** Không đổi ý nghĩa quan trọng ở bộ mẫu; output đúng chiều và lỗi giới hạn rõ. Không dùng exact-string test cho chất lượng LLM.

**Lỗi thường gặp / lưu ý:** Delimiter không bảo đảm chống prompt injection tuyệt đối; app không được thực thi output/model tools. Tách đánh giá ngôn ngữ khỏi parser correctness.

**Rollback:** Quay prompt về bản đã đánh giá tốt; lưu case gây regression.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S23**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S23 — Error handling và recovery

**Mục tiêu:** Lỗi có hành động khắc phục, không loop.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S23 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Chuẩn hóa lỗi permission/selection/runtime/model/network/timeout/malformed stream/input too long/cancelled. Timeout tách cold start và stream stall hợp lý theo đo đạc; retry chỉ chủ động hoặc bounded theo spec, không loop vô hạn. Giữ partial output với nhãn incomplete; không báo cancellation là crash.
Kiểm tra theo mục S23, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** TranslationError.swift, error UI/actions; failure injection tests.

**Lệnh kiểm tra/build:** I, B, T. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Lần lượt mô phỏng từng lỗi; retry rồi đóng panel; thu hồi AX khi app đang chạy.

**Success criteria:** Thông báo ngắn, đúng nguyên nhân, recovery được; app tiếp tục dùng được sau lỗi.

**Lỗi thường gặp / lưu ý:** Không show raw selected text/response trong log lỗi. Không retry tự động tạo nhiều request trùng.

**Rollback:** Hoàn nguyên từng mapping/action; giữ tests mô tả lỗi thực.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S24**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S24 — Trigger khi bôi đen — nếu PLAN yêu cầu

**Mục tiêu:** Bổ sung UX selection tự động đúng scope.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S24 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Đối chiếu PLAN: nếu shortcut-only thì ghi N/A và STOP. Nếu có nút dịch cạnh selection/tự phát hiện selection, implement bằng AX notification khi hỗ trợ và chiến lược fallback đã chốt; debounce, hủy observer khi đổi app, không polling dày hoặc tự gửi text khi chưa đúng trigger trong spec.
Kiểm tra theo mục S24, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** SelectionObserver.swift, selection trigger view nếu áp dụng; lifecycle tests.

**Lệnh kiểm tra/build:** I, B, T; ghi CPU idle nếu có observer/polling. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Kéo chọn, double-click chọn từ, bỏ selection, đổi app, secure field, app không hỗ trợ và nhiều màn hình.

**Success criteria:** Trigger xuất hiện/biến mất đúng, không spam dịch, shortcut vẫn dùng được; app unsupported được ghi rõ.

**Lỗi thường gặp / lưu ý:** AX notification support không đồng nhất. Không mở rộng thành keylogger hoặc OCR để đạt khẩu hiệu “mọi app”.

**Rollback:** Tắt observer/trigger; giữ shortcut path làm baseline.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S25**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S25 — Polish UX

**Mục tiêu:** Hoàn thiện popup và settings trong spec.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S25 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Polish kích thước/scroll, dark mode, typography tiếng Việt, loading, Copy/Close, keyboard navigation và VoiceOver labels. Chỉ thêm settings đã có trong PLAN. Copy chỉ khi người dùng nhấn; không lưu lịch sử dịch nếu spec không yêu cầu.
Kiểm tra theo mục S25, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Popup/settings/assets hiện có; UI checklist.

**Lệnh kiểm tra/build:** I, B, T cho logic thay đổi; kiểm tra UI bằng Xcode runtime. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Nội dung ngắn/dài, font lớn, màn hình nhỏ, dark/light, tab order, VoiceOver và Copy.

**Success criteria:** Không bị cắt nút, panel trong visibleFrame, copy đúng output, keyboard thao tác được.

**Lỗi thường gặp / lưu ý:** Tránh resizable/animation phức tạp làm focus regression. Không cho nút Copy báo thành công khi output rỗng.

**Rollback:** Hoàn nguyên từng thay đổi UI theo diff.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S26**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S26 — Bộ kiểm thử hồi quy

**Mục tiêu:** Tự động hóa phần xác định được.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S26 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Bổ sung tests có giá trị cho permission mapping, routing, endpoint policy/redirect, geometry, parser, cancellation, stale results và error recovery. Network tests dùng mock; unit suite không phụ thuộc Ollama thật hoặc TCC. Không test chỉ để khớp cấu trúc implementation.
Kiểm tra theo mục S26, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Unit/integration tests, fixtures; `docs/TESTING.md`.

**Lệnh kiểm tra/build:** I, B, T; lưu số tests và failure summary. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Review coverage theo SPEC-MAP, chạy lại một failure fixture đã biết.

**Success criteria:** Suite chạy tái lập, không network ngoài máy, không skip phần cốt lõi âm thầm.

**Lỗi thường gặp / lưu ý:** UI/TCC/LLM quality vẫn cần manual test; test pass không chứng minh app hỗ trợ mọi nguồn.

**Rollback:** Hoàn nguyên test lỗi hoặc fixture sai; không xóa test fail hợp lệ để báo xanh.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S27**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S27 — Kiểm thử thực tế và hiệu năng

**Mục tiêu:** Đo chất lượng trải nghiệm trên máy đích.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S27 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Lập matrix app nguồn có trong PLAN và có sẵn: TextEdit, Safari/Chrome, Slack/Notion/VS Code, Mail, PDF reader. Không tự cài app còn thiếu. Test đa màn hình, full-screen, quyền, cold/warm model, offline, rapid triggers và text dài. Đo time-to-first-token/tổng thời gian, RAM và CPU idle; nêu môi trường, không bịa target.
Kiểm tra theo mục S27, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/QA-REPORT.md`, `docs/COMPATIBILITY.md`, bugs với reproduction.

**Lệnh kiểm tra/build:** B, T trước QA; dùng Instruments/Activity Monitor cho số đo; ghi version macOS/Xcode/Ollama/model. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Thực hiện matrix, đánh dấu PASS/FAIL/NOT RUN từng ô; người dùng đánh giá mẫu dịch EN/VI.

**Success criteria:** Đạt tiêu chí PLAN; nếu PLAN không có ngưỡng thì báo số đo để duyệt, không tự tuyên bố đạt.

**Lỗi thường gặp / lưu ý:** Scanned PDF không có text layer khác với AX failure. App không cài là NOT RUN; không phải PASS.

**Rollback:** Không đổi hệ thống để che lỗi; sửa lỗi thuộc scope thành sub-phase riêng có điểm dừng.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S28**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S28 — Rà soát riêng tư và cấu hình phát hành

**Mục tiêu:** Không rò text; chốt đường phân phối.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S28 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Review code/log/storage/endpoint và dependency; xác minh app không có cloud fallback/telemetry nội dung. Review entitlements, sandbox và signing phù hợp cách phân phối đã chốt; đối chiếu Apple docs hiện hành nếu định App Store. Không tắt sandbox hay thêm entitlement rộng chỉ để build qua.
Kiểm tra theo mục S28, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/PRIVACY.md`, `docs/RELEASE.md` phần quyết định; chỉnh config tối thiểu có lý do.

**Lệnh kiểm tra/build:** I, R, T; inspect entitlements của app build bằng `codesign -d --entitlements :- <app-path-thực>`. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Chạy offline, kiểm tra log bằng câu tổng hợp nhận diện được, xác minh chỉ request loopback cho inference.

**Success criteria:** Không lưu text ngoài mục đích đã duyệt; release route và giới hạn quyền rõ.

**Lỗi thường gặp / lưu ý:** Offline test đơn lẻ không chứng minh không rò dữ liệu: kết hợp code review và quan sát network. Không hứa App Store approval.

**Rollback:** Hoàn nguyên entitlement/config theo diff; giữ hồ sơ quyết định.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S29**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S29 — Chuẩn bị release candidate

**Mục tiêu:** Build phát hành tái lập, chưa upload.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S29 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Chốt version/build number theo người dùng và PLAN; hoàn thiện README cài đặt/quyền/Ollama/model/shortcut/troubleshooting/known limitations. Build Release hoặc archive theo route S28. Không upload, notarize, tag hay publish ở bước này.
Kiểm tra theo mục S29, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** README.md, CHANGELOG.md, docs release checklist; Release .app hoặc .xcarchive ngoài Git.

**Lệnh kiểm tra/build:** I, R, T; archive nếu cần: `xcodebuild -project <project-thực> -scheme <scheme-thực> -configuration Release -destination "generic/platform=macOS" -archivePath .build/LocalTranslator.xcarchive archive`. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Chạy đúng Release binary tại path ổn định; thử quyền, shortcut, dịch hai chiều và quit/relaunch.

**Success criteria:** Release candidate chạy được, tài liệu đủ để máy khác setup; tests bắt buộc pass.

**Lỗi thường gặp / lưu ý:** Release signing identity/path có thể khác Debug; không dùng kết quả TCC Debug để suy ra Release.

**Rollback:** Giữ artifact bản trước; hoàn nguyên version/config/docs của bước nếu cần.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S30**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S30 — Signing và notarization — theo kênh phát hành

**Mục tiêu:** Xác minh artifact phân phối ngoài máy nếu được yêu cầu.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S30 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Nếu chỉ dùng local: ghi N/A và STOP. Nếu phân phối ngoài máy: kiểm tra Developer ID, Team và credentials người dùng đã cấu hình; trình đúng artifact và dịch vụ upload trước khi thực hiện. Chỉ ký/notarize artifact đã được người dùng cho phép ở bước này. Không xin gửi password trong chat; không publish link.
Kiểm tra theo mục S30, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** Signed artifact, notarization/staple report trong thư mục build; docs release cập nhật.

**Lệnh kiểm tra/build:** `codesign --verify --deep --strict --verbose=2 <app-thực>`; `spctl --assess --type execute --verbose=4 <app-thực>`; dùng `xcrun notarytool`/`xcrun stapler` theo Apple docs hiện hành và profile thực, không nhét secrets vào command. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Kiểm tra Gatekeeper với artifact phân phối thực; nếu không có credentials, giữ BLOCKED và bàn giao candidate.

**Success criteria:** Kênh phân phối yêu cầu notarization thì có kết quả Accepted và staple/assessment phù hợp; không giả coi unsigned là ready.

**Lỗi thường gặp / lưu ý:** Upload Apple là hành động riêng, không được suy ra từ full permissions. Không có Apple Developer account vẫn có thể dùng local, nhưng không tuyên bố public distribution ready.

**Rollback:** Giữ candidate trước ký; thu hồi/xóa bản upload không được giả định khả thi, không tự động làm.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **S31**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

### S31 — Kiểm thử cài mới và bàn giao

**Mục tiêu:** Xác nhận người dùng cài và chạy được bản cuối.

**Prompt chính xác để paste:**

```text
Chỉ thực hiện S31 trong CODEX_RUNBOOK.md. Đọc Operator protocol, PLAN.md,
AGENTS.md và trạng thái đã được duyệt. Không thực hiện bất kỳ ID nào khác.
Kiểm thử bản đóng gói trên account/máy thử phù hợp nếu có, không reset máy chính. Kiểm tra cài mới, AX permission, Ollama thiếu/model thiếu, offline sau setup, upgrade nếu thuộc PLAN. Tổng hợp release checklist, known issues và đối chiếu SPEC-MAP. Không publish/tag/push.
Kiểm tra theo mục S31, ghi kết quả thực tế và báo phần chưa kiểm chứng.
Sau bước này STOP / WAIT FOR USER CONFIRMATION. Không tự tiếp tục dù thành công.
```

**File/thay đổi dự kiến:** `docs/RELEASE-CHECKLIST.md`, QA report cuối; artifact bàn giao và checksum.

**Lệnh kiểm tra/build:** `shasum -a 256 <artifact-thực>`; signing checks S30 nếu áp dụng; B/T chỉ cần chạy lại nếu có thay đổi sau lần pass cuối. Ký hiệu I/B/T/R dùng lệnh tại mục 2, điền đúng path/scheme; không chạy placeholder nguyên văn.

**Manual checks:** Người dùng thử luồng select → shortcut/trigger → stream → copy/close bằng release build.

**Success criteria:** Mọi yêu cầu bắt buộc có bằng chứng hoặc blocker; người dùng duyệt nghiệm thu. Bản chưa test máy sạch phải ghi rõ.

**Lỗi thường gặp / lưu ý:** Đừng gộp “release prep” với phát hành công khai. Publish chỉ là task mới có xác nhận riêng.

**Rollback:** Giữ bản phát hành trước, hướng dẫn quay lại bản đó; không xóa model/quyền/dữ liệu người dùng.

**STOP / WAIT FOR USER CONFIRMATION**

Báo cáo theo mẫu mục 1. Chỉ sau xác nhận mới được thực hiện **nghiệm thu cuối (không có bước tự động tiếp theo)**. Nếu cần một sub-phase sửa lỗi, sub-phase đó cũng phải kết thúc bằng STOP riêng.

## 4. Khi chat bị ngắt hoặc cần tiếp tục ở chat khác

Paste prompt này; thay Sxx bằng đúng bước muốn giao:

```text
Đọc PLAN.md, AGENTS.md, CODEX_RUNBOOK.md và docs/PROGRESS.md.
Kiểm tra trạng thái repo thật; không coi ghi chú “đã làm” là bằng chứng build pass.
Chỉ tiếp tục Sxx, không chạy lại các bước hoàn tất và không chạy bước sau.
Nếu không rõ bước cuối đã được tôi duyệt, báo trạng thái và chờ tôi xác nhận.
Sau Sxx bắt buộc STOP / WAIT FOR USER CONFIRMATION.
```

Mẫu `docs/PROGRESS.md`:

```markdown
| ID | Trạng thái | Bằng chứng | Manual check còn thiếu | Người dùng duyệt |
|---|---|---|---|---|
| S01 | PASS | Xcode version + PLAN path | Không | Nội dung xác nhận thực tế |
| S02 | NOT RUN | — | — | Chưa |
```

Không điền trước PASS, timestamp xác nhận hoặc checkpoint không có thật.

## 5. Tài liệu kỹ thuật tham chiếu

Tra cứu lại theo SDK/runtime thực tế khi triển khai; các URL này không mở rộng scope PLAN.md.

- [Apple AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement): truy cập Accessibility của app nguồn.
- [Apple NSPanel](https://developer.apple.com/documentation/appkit/nspanel): cửa sổ panel macOS.
- [Apple NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer): nhận diện ngôn ngữ local.
- [Ollama API: Chat](https://docs.ollama.com/api/chat): endpoint `/api/chat`, tham số `stream`, trường `message.content` và `done`.
- [Ollama macOS](https://docs.ollama.com/macos): cài đặt và yêu cầu runtime.
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): kiểm tra trước phân phối.

**Điểm kết thúc:** S31 chỉ bàn giao để nghiệm thu. Không có quyền ngầm để publish, tạo release, push repo hoặc bắt đầu feature mới.
