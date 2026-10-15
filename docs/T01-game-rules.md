# T01 — GAME RULES / DOMAIN SPECIFICATION — WEREWOLF HASKELL

> **Đường dẫn đích:** `docs/game-rules.md`  
> **Phạm vi:** 8 hoặc 9 người; Server-authoritative; quy tắc nghiệp vụ cho T02–T07 và hợp đồng tích hợp Server/Protocol/Test.  
> **Thứ tự ưu tiên:** (1) bản **CHỐT LUẬT T01 – BẢN ĐƠN GIẢN** của leader; (2) sheet chính thức `03 - LUẬT & THIẾT KẾ` và yêu cầu T01 của `02 - WORKFLOW & TASK`; (3) chi tiết bổ sung theo luật truyền thống [T] hoặc quy ước kỹ thuật [K] tại mục 16. Sheet `LEGACY` và bản Git cũ chỉ để đối chiếu, không được ghi đè luật leader.  
> **Trạng thái phê duyệt:** Các điều khoản ký hiệu **[L]** là do leader chốt; **[S]** là ràng buộc Sheet; **[P]** là đặc tả bổ sung trước đây, được chốt làm **mặc định đề xuất áp dụng** theo bảng quyết định ở mục 16 (nguồn [T] nếu dựa luật truyền thống, [K] nếu là quy ước kỹ thuật). Đây là bản đề xuất hoàn thiện để nhóm phê duyệt/merge, **không phải bằng chứng leader đã duyệt** các bổ sung.

## 1. Danh mục quy tắc và nguồn

| ID | Nhóm | Cơ sở | Yêu cầu bắt buộc |
|---|---|---|---|
| CFG | Số người/vai | [L], [S] | Chính xác 8 hoặc 9, vai đúng preset; 9 là demo chính |
| LOB | Lobby/Start | [L], [S] | Host + toàn bộ Ready + đúng preset + Lobby |
| PHS | Phase | [S] | `Lobby → Night → Day → Voting → Night` hoặc `GameOver` |
| WOL | Werewolf | [L] | Chọn dân còn sống; hòa phiếu cao nhất = không cắn |
| SEE | Seer | [L] | Xem người còn sống khác; chỉ gửi riêng kết quả Team |
| GRD | Guard | [L] | Tự bảo vệ được; không trùng mục tiêu hai đêm liên tiếp; chỉ chặn Sói |
| WIT | Witch | [L] | Heal hoặc Poison hoặc Pass; mỗi bình một lần; Heal chỉ chặn Sói |
| HUN | Hunter | [L] | Khi chết bất kỳ nguyên nhân, bắn tối đa một người; timeout bỏ qua; xét thắng sau bắn |
| DAY | Day/Chat | [L], [S] | Người sống chat `PublicDay` ở Day; Sói sống chat `WolvesNight` ở Night; không thay đổi gameplay state |
| VOT | Voting | [L] | Mỗi người một phiếu; không tự chọn; hòa/không phiếu = không loại, không vote lại |
| WIN | Win/Draw | [L] | Không người sống = Draw; hết Sói = Village; Sói >= Dân = Wolves |
| REV | Role Reveal | [L], [S] | Giữ bí mật Role/Team của mọi Player (kể cả Dead) đến `GameOver`; chỉ công khai trạng thái Dead |
| ENG | Engine/Events | [S] | Pure `applyCommand`, `Either GameError`, privacy, idempotency, concurrency, replay |
| UI | Dashboard/Appearance/Ability/Chat UX | [L], [S] | Dashboard 3×3 xuyên pha, ngoại hình công khai, ability riêng tư, mục tiêu hợp lệ, chat lịch sử, bubble và hướng dẫn |

## 2. Preset người chơi — CFG

| Role | Team | 8 người | 9 người |
|---|---|---:|---:|
| Werewolf | Wolves | 2 | 3 |
| Seer | Village | 1 | 1 |
| Guard | Village | 1 | 1 |
| Witch | Village | 1 | 1 |
| Hunter | Village | 1 | 1 |
| Villager | Village | 2 | 2 |
| **Tổng** | | **8** | **9** |

- **CFG-01 [L]:** Chỉ số người **8 hoặc 9** mới được `StartGame`. 7/10 người và mọi trường hợp khác: `InvalidPlayerCount`; 8 người không cần chờ người thứ 9.
- **CFG-02 [L]:** Vai phải khớp **chính xác multiset** tương ứng số người. Không tự bỏ vai đặc biệt, không thêm vai mới. 8 người có 2 Sói + 6 Dân; 9 người có 3 Sói + 6 Dân. [S] Ván 9 người được ưu tiên làm demo.
- **CFG-03 [S]:** Role là thông tin server nắm giữ. Team xác định bằng `teamOf Werewolf = Wolves`, các role khác thuộc `Village`; không có phe thứ ba. Mỗi người có một ID ổn định, một vai sau Start.
- **CFG-04 [P]:** Trong Lobby role chưa được gán (`Maybe Role`); random shuffle do Server cung cấp seed/hoán vị hợp lệ, Domain xác nhận preset trước khi commit; role không tự thay đổi sau Start.

**Pattern cases:** Happy: 8 người đủ Ready/Host với 2 Sói được Start; 9 người với 3 Sói được Start. Error: 8 người nhưng 3 Sói → `InvalidConfiguration`; 7 hoặc 10 người → `InvalidPlayerCount`. Edge: 8 người đang Lobby nhận thêm người thứ 9 → vẫn có thể Start nếu toàn bộ 9 Ready, lúc này **phải** dùng preset 9, không giữ preset 8.

## 3. Lobby, Host, Ready, Start — LOB

**Specification**

- **LOB-01 [S]:** `Join`: chỉ trong Lobby; ID chưa tồn tại, tên hợp lệ, số thành viên chưa đủ 9; thêm người và phát `PlayerJoined`. `Leave`: chỉ trong Lobby; loại người và phát `PlayerLeft`. Reconnect **không phải** Join mới.
- **LOB-02 [S]:** `SetReady` chỉ tại Lobby cho người đã ở phòng; người chơi có thể chuyển Ready/NotReady, phát `ReadyChanged` khi có thay đổi.
- **LOB-03 [L]:** `StartGame` thành công **iff** đồng thời: `phase == Lobby`, `playerCount ∈ {8,9}`, **tất cả player đã Ready**, actor **đúng Host**, role preset hợp lệ. Kiểm tại thời điểm Server xử lý, không tin nút Start trên UI.
- **LOB-04 [S]:** Khi Start thành công: gán đúng role, khởi tạo alive, witch potions/guard history/hunter status/night votes; chuyển Night đầu tiên; phát `GameStarted`, `PhaseChanged`, **PrivateRoleAssigned** cho từng người. Không broadcast role.
- **LOB-05 [P]:** ID người chơi không trùng, tên hiển thị sau trim phải có ký tự; nếu tên trùng thì từ chối để UI dễ phân biệt. Host rời Lobby: chuyển quyền Host cho người còn lại có thứ tự Join sớm nhất; phòng rỗng xóa phòng. Người rời rồi vào lại trước Start trở thành thành viên mới và NotReady. Chi tiết này cần leader duyệt.

**Pattern cases:** Happy: Host Start sau 8/9 Ready. Error: khách Start → `NotAuthorized`; một người NotReady → `NotReady`; Start lần hai → `WrongPhase`/`GameAlreadyStarted`; Join trùng ID → `PlayerAlreadyExists`. Edge: cùng lúc một người Unready và Host Start → transaction quyết định thứ tự; Start chỉ thành công nếu snapshot lúc kiểm vẫn toàn Ready. Host rời trước Start → áp dụng [P] chuyển Host.

## 4. Phase / state machine — PHS

```text
Lobby --(valid StartGame)--> Night
Night --(resolve + all deaths/Hunter + checkWin=None)--> Day
Night --(resolve + all deaths/Hunter + checkWin=Just result)--> GameOver
Day --(EndDiscussion / timeout)--> Voting
Voting --(resolve + all deaths/Hunter + checkWin=None)--> Night
Voting --(resolve + all deaths/Hunter + checkWin=Just result)--> GameOver
```

- **PHS-01 [S]:** Domain/Server quyết định phase và phát `PhaseChanged`. Client chỉ render theo event/snapshot.
- **PHS-02 [L]:** **Không** gọi `checkWin` khi còn Hunter shot đang chờ xử lý. Win check sau resolve Night và sau resolve Voting; Day không làm ai chết theo rule hiện hành nên không tự tạo kết quả thắng mới.
- **PHS-03 [P]:** `dayNumber` bắt đầu ở 1 với Night đầu tiên; vòng mới tăng +1 khi Voting → Night; không reset tiêu hao potion/history Guard.
- **PHS-04 [P]:** Day kết thúc bằng server tick/timeout hoặc internal `EndDiscussion`; Night/Voting kết thúc bằng internal `ResolveNight`/`ResolveVoting` do server định thời. Internal command **không** được client mạo danh.
- **PHS-05 [S]:** GameOver bất biến: từ chối gameplay commands; `RequestSnapshot` vẫn được phép để xem kết quả (đây là read-only, không phải game action).

**Pattern cases:** Happy: Night 1 → Day 1 → Voting 1 → Night 2. Error: Vote trong Night, Chat trong Voting, NightAction trong Day → `WrongPhase`. Edge: cuối Night giết hết người sống → đi thẳng GameOver Draw, **không** thoáng qua Day rồi tính thắng.

## 5. Night action: rules chung — NGT

- **NGT-01 [L,S]:** Actor phải tồn tại, còn Alive, đúng Role, đúng Night; target ID tồn tại, Alive ở snapshot đêm, hợp lệ theo từng vai. Role không có kỹ năng (Villager) không được submit.
- **NGT-02 [P]:** Mỗi role-action chỉ được **chấp nhận một lần trong một đêm**; không sửa lựa chọn bằng request khác. Sói mỗi người một vote; Seer/Guard/Witch mỗi người một action (Witch chọn **một** trong Heal, Poison, Pass). Lệnh trùng requestId phải idempotent theo §14, không tính lại.
- **NGT-03 [P]:** Không gửi đúng hạn = abstain/pass, **không** tự giết ai, không tiêu potion, không thay target trước đó; countdown cấu hình bên Server. Người vừa mất mạng **không** chuyển Dead.
- **NGT-04 [P]:** Snapshot chọn target là người sống **ở đầu Night**; mọi vote/action hợp lệ được resolve đồng thời theo thuật toán §10, nên chết do đêm không làm action hợp lệ đã gửi biến mất; Hunter shot là hậu hiệu ứng.
- **NGT-05 [S]:** Action bí mật, chỉ gửi acknowledgment cho actor. Không công bố target của Sói, Guard, Witch hay Seer cho tất cả; riêng tiến độ chọn của Sói được gửi `TeamOnly` tới Sói còn sống trong cùng phòng, không gửi tới phe khác. Không tiết lộ hành động Seer/Guard/Witch.

**Pattern cases:** Happy: Seer chọn Villager và nhận `Village` riêng. Error: dead actor, target ID sai, role sai → Left, không đổi state/event. Edge: disconnect trong Night → action trước đó vẫn tính; thiếu action → skip theo [P].

## 6. Werewolf — WOL

- **WOL-01 [L]:** Mỗi Werewolf còn sống gửi **tối đa một** lựa chọn một Player **Alive** thuộc **Village**, không bao giờ chọn chính mình hoặc Sói khác.
- **WOL-02 [L]:** Tally chỉ phiếu Sói hợp lệ nhận đúng lượt; chỉ khi **một target có phiếu cao nhất duy nhất** mới có `wolfVictim`. Hòa cao nhất, hoặc không có phiếu: `wolfVictim = Nothing`.
- **WOL-03 [L]:** Sói chết không được gửi vote.
- **WOL-04 [L,S]:** Sói còn sống có kênh `WolvesNight` riêng trong Night để thảo luận và xem tiến độ bỏ phiếu. Thông tin đồng đội, chat và phiếu Sói không phát tới Village. `WolfVoteUpdated` (tiến độ, chỉ gửi TeamOnly) và `WolfTargetLocked` (thông báo chốt đúng người được phép biết) là contract đề xuất cho T02/T05/T08. **Không thay thuật toán WOL-02 thành đồng thuận 100%.** Khi mọi Sói sống đã vote có thể chốt sớm; nếu hết thời hạn, chỉ kiểm các phiếu hợp lệ đã nhận theo WOL-02.

**Pattern cases:** Happy 9 người: W1→A, W2→A, W3→B ⇒ A; 8 người: W1→A, W2→A ⇒ A. Error: W1→W2 hoặc dead target ⇒ `InvalidTarget`; dead W1 vote ⇒ `DeadPlayer`. Edge: 8 người W1→A, W2→B ⇒ tie ⇒ Nothing; 9 người mỗi Sói chọn 1 người khác nhau ⇒ Nothing; chỉ còn 1 Sói ⇒ một phiếu hợp lệ quyết định nạn nhân; không phiếu ⇒ Nothing.

## 7. Seer — SEE

- **SEE-01 [L]:** Seer Alive mỗi Night có quyền kiểm tra tối đa một Player Alive khác mình; không chọn bản thân.
- **SEE-02 [L]:** Kết quả = `Wolves` nếu target Werewolf, bằng `Village` với mọi role còn lại; **chỉ Seer** nhận `PrivateResult`.
- **SEE-03 [P]:** Seer chỉ nhận kết quả sau khi action hợp lệ được xử lý; đây là kết quả về Team của target trong đêm, không lộ Role cụ thể.

**Pattern cases:** Happy: check Werewolf ⇒ Wolves; check Witch ⇒ Village. Error: tự check, dead target, check lần hai trong một Night ⇒ Left. Edge: Seer bị Poison trong đêm vẫn nhận kết quả riêng đã phát/được ghi nhận nếu action hợp lệ, nhưng không được hành động đêm sau [P]; không để kết quả lọt public event.

## 8. Guard — GRD

- **GRD-01 [L]:** Guard Alive bảo vệ tối đa một Player Alive, **có thể tự bảo vệ**.
- **GRD-02 [L]:** Không được chọn **cùng target của hai đêm liên tiếp**; Guard block **Werewolf Kill**, không block Witch Poison hoặc Hunter Shot.
- **GRD-03 [P]:** `lastGuardTarget` lưu target ở **Night trước theo số đêm**; nếu Night trước Guard Pass/không gửi thì last = Nothing, nên đêm sau có thể chọn lại người từng bảo vệ hai đêm trước. Một action lỗi không cập nhật history; action hợp lệ mới ghi mục tiêu.

**Pattern cases:** Happy: N1 Guard tự bảo vệ; N2 bảo vệ A. Error: N2 bảo vệ A sau N1 cũng A ⇒ `ConsecutiveGuardTarget`. Edge: N1→A, N2 Pass, N3→A ⇒ hợp lệ theo [P]; Guard bảo vệ A nhưng A bị Poison ⇒ A vẫn chết; Guard bảo vệ A và Sói chọn A ⇒ không chết bởi Sói.

## 9. Witch — WIT

- **WIT-01 [L]:** Đúng **một** trong `Heal | Poison target | Pass` mỗi Night; **không** bao giờ vừa Heal vừa Poison cùng đêm.
- **WIT-02 [L]:** Có một Heal potion, một Poison potion; **mỗi loại dùng tối đa một lần toàn game**. Potion chỉ tiêu hao sau action **hợp lệ**; action bị từ chối không đổi potion.
- **WIT-03 [L]:** Heal hủy **Werewolf Kill của đêm đó**, có thể tự cứu nếu mình là wolf victim; nếu không có wolf victim hợp lệ, Heal không hợp lệ và không mất bình.
- **WIT-04 [L]:** Poison yêu cầu target Alive, khác Witch; không bị Guard hoặc Heal ngăn; không Poison chính mình.
- **WIT-05 [P]:** Server chỉ cho Witch thông tin cần thiết để chọn Heal mà không tiết lộ role/vote của Sói; để hỗ trợ Heal sau vote Sói, server đóng **substage wolf collection** rồi mở **Witch decision** (Guard/Seer vẫn làm trong Night). Witch Heal là lựa chọn không cần truyền target ID (tự nhắm vào `wolfVictim`), không phải bấm chọn người tùy ý. Nếu chưa đến Witch decision, Heal sẽ bị từ chối `ActionNotAvailableYet`.
- **WIT-06 [P]:** Nếu Witch còn cả hai potion, việc `Pass` không tiêu potion. Một potion đã tiêu hao không hồi lại sau chuyển phase/disconnect.

**Pattern cases:** Happy: wolfVictim=A, Witch Heal ⇒ A sống nếu không bị Poison/Hunter; Poison B ⇒ B chết. Error: Heal khi wolfVictim=None ⇒ `NoWolfVictim`; Heal hết bình/Poison hết bình ⇒ `AbilityAlreadyUsed`; Poison self ⇒ `InvalidTarget`; cả hai cùng lúc ⇒ `MultipleWitchActions`. Edge: Guard cũng bảo vệ A, Witch Heal A vẫn tiêu bình nếu chủ động Heal khi wolfVictim tồn tại [P]; Witch tự Heal khi bị cắn ⇒ sống; Witch Poison A khi Sói cắn A ⇒ A chết một lần; Witch bị Sói cắn vẫn có thể chọn Heal trong đêm đó theo staged Night [P].

## 10. Resolve Night / death effects — RES

**Specification — thứ tự xác định, không phụ thuộc thời điểm network packet ngoài thứ tự nhận action:**

1. Chốt tập người sống ở đầu đêm và các action hợp lệ; tính wolf tally → `wolfVictim :: Maybe PlayerId`.
2. Guard xác định `guardTarget :: Maybe PlayerId`.
3. Witch action hợp lệ xác định `healedWolfAttack :: Bool` hoặc `poisonTarget :: Maybe PlayerId` (không thể cùng true/nonempty do WIT-01).
4. `wolfDeath = wolfVictim`, **chỉ nếu** Guard không chặn và Witch không Heal. `poisonDeath = poisonTarget` độc lập.
5. Hợp nhất `wolfDeath` và `poisonDeath` thành **tập ID**: mỗi người Alive→Dead đúng **một** lần, giữ cause(s) nội bộ khi cần.
6. Với mọi Hunter mới chết, tạo **pending shot**; mở bước Hunter response, xử lý shot/timeouts cho đến khi không còn pending effect; mọi target mới phải Alive lúc shot được submit.
7. **Chỉ khi pending shot rỗng** mới `checkWin` theo §13; nếu `Just result` → GameOver, nếu Nothing → Day và công bố người chết theo chính sách §15.

**RES-01 [L]:** Guard và Heal chặn **chỉ** Werewolf Kill; Poison và Hunter Shot luôn không bị chặn. Hunter được bắn bất kể chết do wolf, poison, vote hay Hunter shot.

**RES-02 [P]:** Nhiều causes trên cùng ID → một lần chuyển Dead, một event death; nếu Hunter đã chết trong cùng resolve thì bắn **một lần**. Hành động đêm khác đã được xác nhận không bị thu hồi do actor chết trong cùng đêm. Hành động tới sau khi Night đã khóa → `WrongPhase` / `ActionWindowClosed`.

**Pattern cases:** Happy: Wolves→A, Guard→A, Witch→Poison B ⇒ A sống B chết. Error: submit action ngoài window ⇒ Left. Edge: Wolves→Hunter, Witch→Poison Hunter ⇒ Hunter chỉ chết một lần và bắn một lần; Heal wolf target đồng thời Poison target đó (chỉ có thể qua nguồn khác? không trong cùng đêm vì Witch giới hạn 1 action) không xảy ra từ một Witch; Hunter bắn Hunter đã Dead ⇒ InvalidTarget; sau shot số người sống =0 ⇒ Draw.

## 11. Hunter — HUN

- **HUN-01 [L]:** Khi Hunter chuyển **Alive→Dead**, **bất kể nguyên nhân**, kích hoạt quyền bắn **đúng một lần tối đa** (không phân biệt Wolf, Poison, Vote, Shot). Việc bắn là tùy lựa chọn: hết timeout không chọn thì Skip.
- **HUN-02 [L]:** Target phải **khác Hunter**, tồn tại, **Alive vào thời điểm bắn**. Hunter đã chết được phép **duy nhất** gửi command đặc biệt để thực hiện **pending HunterShot** của chính mình.
- **HUN-03 [L]:** Shot không bị Guard hoặc Witch Heal chặn. Xử lý shot/xếp hàng pending **trước** khi checkWin; không tái kích hoạt Hunter đã dùng skill.
- **HUN-04 [P]:** Khi Hunter chết, chuyển sang pending-shot substate nội bộ (giữ phase Night/Voting), phát private prompt; nhận `HunterShoot target` hoặc internal `HunterTimeout`. **Không** chạy điều kiện DeadPlayer thông thường trước khi kiểm quyền pending shot. Nếu Hunter là role duy nhất trong preset, chain shot không tạo Hunter thứ hai; code vẫn nên có hàng đợi effect tổng quát.

**Pattern cases:** Happy: Hunter bị Vote loại, bắn A, A chết, sau đó checkWin. Error: bắn chính mình, bắn dead target, bắn lần hai ⇒ Left. Edge: Hunter chết do Witch Poison ⇒ vẫn bắn; Hunter chết do Hunter Shot (với mở rộng role/preset khác) ⇒ vẫn chỉ bắn một lần; timeout ⇒ bỏ qua rồi checkWin; chỉ còn Hunter và 1 Sói, Hunter chết và bắn Sói ⇒ có thể Draw nếu không còn ai sống.

## 12. Day, Chat và Voting — DAY / VOT

### DAY — Chat (theo kênh)

- **DAY-01 [L,S]:** `PublicDay`: chỉ người **Alive** trong đúng phòng gửi tin khi `Phase = Day`; văn bản sau trim không rỗng. Tin hiển thị trong khung chat chung, được đánh dấu ngày tương ứng.
- **DAY-02 [L,S]:** `WolvesNight`: chỉ người **Alive**, giữ vai Werewolf và thuộc đúng phòng gửi/nhận tin **khi `Phase = Night`**. Các vai khác, Sói đã chết, người ngoài phòng không được nhận nội dung hoặc lịch sử riêng của kênh Sói.
- **DAY-03 [L,S]:** Người Dead không được gửi chat hoặc thực hiện action/vote thường; ngoài hai tổ hợp kênh–phase trên, `SendChat` bị từ chối. Chat không thay đổi gameplay GameState (phase, alive, votes, role, potions); lịch sử có thể lưu trong server-side chat store riêng với Domain GameState.
- **DAY-04 [S,L]:** Khi bắt đầu mỗi Day, có mốc `Ngày N bắt đầu`; tin các ngày trước vẫn xem lại được. Reconnect/reload trong **cùng ván** phải khôi phục history theo phòng, kênh, thứ tự và quyền người nhận. Chat `PublicDay` và `WolvesNight` hiển thị và lưu tách biệt; không phát sót payload `WolvesNight` sang người không có quyền.
- **DAY-05 [L,S]:** Event chat gồm định danh phòng, ngày, kênh, messageId, sequence, senderId, text (chi tiết ở T02/T07). Bong bóng tin trên ô người gửi chỉ là hiệu ứng giao diện 3–5 giây, có rút gọn tin dài; riêng bong bóng của Sói chỉ hiện với recipient được phép xem chat Sói. Tin luôn giữ trong history dù bong bóng biến mất.
- **DAY-06 [K]:** Khôi phục chat qua reconnect trong khi tiến trình Server còn giữ state là yêu cầu bắt buộc. **Không mặc định bảo đảm** khôi phục qua lần Server tắt/khởi động lại nếu chưa có persistent storage (DB hoặc cơ chế bền vững tương đương); cần task riêng nếu muốn mức bảo đảm đó.
- **DAY-07 [S]:** Vào Day chỉ công khai người chết bằng trạng thái Dead/ID theo REV, không lộ Role/Team. Day → Voting theo internal timer/transition của Server.

**Pattern cases:** Happy: Alive A gửi tin PublicDay trong Day; Werewolf Alive gửi WolvesNight trong Night, chỉ đồng đội hợp lệ nhận. Error: text whitespace ⇒ `EmptyChat`; Dead gửi chat ⇒ `DeadPlayer`; Villager truy cập WolvesNight ⇒ `NotAuthorized`; chọn sai phase/kênh ⇒ `WrongPhase`. Edge: Unicode; reconnect đúng room và cùng role nhận lại đúng lịch sử theo sequence; người ngoài phe không thấy chat Sói; chat nhiều ngày vẫn còn.

### VOT — Bỏ phiếu

- **VOT-01 [L]:** Chỉ Alive player, **đúng Voting**, được chọn target khác mình, tồn tại, Alive. Mỗi voter **tối đa một phiếu cho một round**.
- **VOT-02 [L]:** Target có **số phiếu cao nhất duy nhất** bị loại; hòa cao nhất hoặc không phiếu ⇒ **không ai chết**. **Tuyệt đối không vote lại**.
- **VOT-03 [L]:** Sau quyết định loại: resolve Hunter pending → checkWin; nếu chưa kết thúc chuyển Night kế tiếp.
- **VOT-04 [P]:** Cho phép voter **bỏ phiếu trắng bằng không gửi phiếu**; timeout chốt mọi phiếu đã nhận, không tính fake vote. Đã Vote không được đổi lựa chọn cùng round; receipt trùng requestId không tính thêm.

**Pattern cases:** Happy: A/B/C vote D, E vote F ⇒ D chết. Error: self-vote, dead target, dead voter, vote lần 2, Vote khi Night ⇒ Left. Edge: 2 phiếu A và 2 phiếu B ⇒ không loại; 0 phiếu ⇒ không loại; chỉ 1 phiếu hợp lệ ⇒ target đó chết; Hunter bị lynch và bắn người cuối cùng làm thay đổi kết quả thắng.

## 13. Win condition — WIN

**Kiểm tra CHÍNH XÁC theo thứ tự ưu tiên leader sau khi hết toàn bộ Death Effects:**

```haskell
data GameResult = Winner Team | Draw deriving (Eq, Show)

checkWin :: GameState -> Maybe GameResult
checkWin gs
  | aliveW + aliveV == 0 = Just Draw
  | aliveW == 0          = Just (Winner Village)
  | aliveW >= aliveV     = Just (Winner Wolves)
  | otherwise            = Nothing
  where
    aliveW = countAlive Wolves gs
    aliveV = countAlive Village gs
```

- **WIN-01 [L]:** Không ai Alive: `Draw`, **ưu tiên cao nhất**, kể cả đồng thời hết Sói.
- **WIN-02 [L]:** Có ít nhất 1 người sống và Sói Alive = 0 ⇒ Village thắng.
- **WIN-03 [L]:** Có Sói Alive và số Sói >= số Village Alive ⇒ Wolves thắng; Village đếm mọi role không phải Werewolf.
- **WIN-04 [L]:** Còn lại tiếp tục. Không checkWin trong Lobby, trước khi game bắt đầu, hoặc khi Hunter pending.
- **WIN-05 [S]:** Khi thắng/hòa: `phase=GameOver`, lưu `GameResult`, phát đúng một `GameEnded`, mọi game action về sau không hợp lệ.

| Wolves Alive | Village Alive | Kết quả |
|---:|---:|---|
| 0 | 0 | Draw |
| 0 | 1 | Winner Village |
| 1 | 0 | Winner Wolves |
| 1 | 1 | Winner Wolves |
| 2 | 2 | Winner Wolves |
| 2 | 3 | Continue |
| 3 | 6 | Continue |

**Pattern cases:** Happy: Hunter shot giết Sói cuối, còn dân sống ⇒ Village. Error: client tự yêu cầu GameEnded hay checkWin giữa pending shot ⇒ `NotAuthorized` / không chấp nhận internal transition. Edge: Hunter chết và bắn chết người sống cuối ⇒ Draw; 2 Sói và 2 dân sau Night ⇒ Wolves; trước Hunter Shot đang 1 Sói / 1 Dân thì **chưa** được kết thúc.

## 14. Validation, errors, invariants, pure engine — ENG

**API Domain [S]:**

```haskell
applyCommand :: GameState -> Command -> Either GameError (GameState, [DomainEvent])
```

Server cấp authenticated actor, clock/timer trigger, RNG role assignment và request metadata đã kiểm tra (đưa qua Command/explicit dependencies) để logic là **pure**, không `IO`, không đọc đồng hồ hay random bên trong hàm.

**Validation order [P] (để lỗi deterministic):** 1) GameOver (trừ read-only), 2) xác thực actor/đúng quyền nội bộ, 3) phase, 4) player/Alive (ngoại lệ pending Hunter), 5) role, 6) target, 7) lượt/ability/potion, 8) atomic transition + invariants. Nếu hai điều kiện cùng sai, trả lỗi ưu tiên đầu tiên theo thứ tự này.

| GameError đề xuất | Khi nào |
|---|---|
| `WrongPhase`, `GameAlreadyStarted`, `GameAlreadyOver` | Phase sai, Start lại, action sau GameOver |
| `PlayerNotFound`, `PlayerAlreadyExists`, `InvalidPlayerCount`, `RoomFull`, `InvalidPlayerName` | Join/roster không hợp lệ |
| `NotAuthorized`, `NotReady`, `InvalidConfiguration` | Start/quyền/preset sai |
| `DeadPlayer`, `RoleCannotAct`, `InvalidTarget` | Actor, skill hoặc target không hợp lệ |
| `AlreadyActed`, `AlreadyVoted`, `AbilityAlreadyUsed`, `ConsecutiveGuardTarget` | Dùng lại action/vote/potion/guard |
| `NoWolfVictim`, `MultipleWitchActions`, `ActionNotAvailableYet`, `ActionWindowClosed` | Witch hoặc thời điểm action sai |
| `EmptyChat`, `NoPendingHunterShot`, `DuplicateRequest` | Chat/Hunter/request không hợp lệ |

**Invariant [S,L]:**

1. PlayerIds duy nhất; roster sau Start có đúng preset 8/9 và chỉ có Role/Team được server gán.
2. Player Alive→Dead tối đa 1 lần; không resurrect, trừ khi luật mới cho phép (hiện **không có**).
3. Dead không NightAction/Vote/Chat; **ngoại lệ duy nhất** là Hunter với pending-shot một lần.
4. Command sai phase/target/role/quyền ⇒ `Left`, không state change, không emit success event.
5. Một Vote mỗi voter một Voting; một role-action mỗi Night [P]; Witch potion mỗi loại tối đa 1 lần toàn game.
6. Guard không lặp target ở **hai Night sát nhau**; Guard không chặn poison/shot.
7. Đã GameOver thì result cố định và không có gameplay transition; không có GameEnded lặp.
8. Kết quả riêng/secret action và **Role/Team của tất cả Player (Alive hoặc Dead)** không được leak qua public event, snapshot, chat payload hoặc log **trước GameOver**. Ngoại lệ duy nhất là thông tin Team được phép trả riêng cho Seer và danh sách đồng đội Sói được phép nhận theo luật. Sau GameOver, công bố toàn bộ vai qua `GameRolesRevealed`.
9. Khi pending Hunter Shot chưa resolve không có Winner/Draw kết luận sớm.
10. STM/serial command commit giữ nguyên mọi invariant; replay cùng initial seed + chuỗi accepted commands/timer inputs ⇒ state/events bằng nhau.

**Pattern cases:** Happy command hợp lệ ⇒ `Right (s', events)` giữ invariants. Error invalid command ⇒ `Left e` (Server không commit). Edge: 2 Vote đồng thời ⇒ xử lý tuần tự/STM, không lost update; requestId lặp ⇒ không áp dụng action lần thứ hai.

## 15. Domain Event, visibility, Protocol và Server contract

`EventVisibility` phân thành `Public`, `Private recipientId` và `TeamOnly Wolves` (kiểm tra **room, phase, alive và vai thật tại Server**; không tin claim từ Browser). Các type/constructor cuối cùng do T02 và T08 thống nhất; tên dưới đây là contract mong đợi, không khẳng định đã có trong source.

| Event / dữ liệu | Visibility | Ghi chú |
|---|---|---|
| `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `GameStarted`, `PhaseChanged` | Public | Chỉ dữ liệu công khai: PlayerId, tên, Appearance, Ready/Alive; không kèm vai |
| `PrivateRoleAssigned`, `YourRole`, `RoleAbilityInfo` | Private — chủ sở hữu | Có Role và mô tả khả năng; không phát qua event công khai |
| `PrivateSeerResult` | Private — Seer | Chỉ Team được soi, không lộ Role cụ thể |
| `WitchVictimNotice` | Private — Witch | Chỉ dữ liệu đủ Heal, không kèm danh sách phiếu Sói |
| `NightActionAccepted` | Private — actor | Receipt riêng, không lộ hành động của vai khác |
| `WolfVoteUpdated` | TeamOnly — Sói còn sống cùng phòng | Tiến độ lựa chọn, không public; payload tối thiểu, không rò bí mật vai khác |
| `WolfTargetLocked` | TeamOnly — Sói còn sống (hoặc server-internal) | Kết quả khóa theo WOL-02, không phát mục tiêu sang Village |
| `VoteUpdated` (ban ngày) | Public, nội dung [P] | Có thể phát tổng số phiếu, không lộ ai bầu ai trước resolve |
| `PlayerDied` (`PlayerEliminated` tương thích) | Public | PlayerId, Dead và metadata công khai hợp lệ; **không có Role/Team** |
| `NightResolved` | Internal / Public đã lọc | Không kèm target, Role, Team hay secret action chưa được phép công bố |
| `HunterShotPrompt` | Private — Hunter pending | Ngoại lệ hành động của Dead Hunter |
| `ChatMessage(PublicDay)` | Public — đúng phòng | Lưu lịch sử theo ngày; chỉ Alive gửi trong Day |
| `ChatMessage(WolvesNight)` | TeamOnly — Sói được quyền | Chỉ Sói sống trong Night, history lọc theo quyền |
| `GameEnded` | Public | Winner Village/Wolves hoặc Draw, không kết thúc khi Hunter pending |
| `GameRolesRevealed` | Public — **chỉ GameOver** | Danh sách PlayerId → Role/Team thật cho **tất cả** người chơi, kể cả Dead |

### 15.1. REV — Trạng thái chết công khai, vai trò bí mật đến GameOver

> **[L,S] Ưu tiên yêu cầu Leader và Excel bổ sung (2026-10-14):** Không áp dụng thông lệ lật vai khi chết của luật Ma Sói truyền thống [R3]. Tất cả Role/Team vẫn là thông tin bí mật trong trận, bất kể player sống hay chết. Đây là thay đổi chính thức về **yêu cầu nghiệp vụ mới**, khác bản REV cũ.

- **REV-01 [L]:** Sau phân vai, Role/Team và mô tả khả năng chỉ được gửi riêng cho chủ sở hữu; không công khai vai người khác trước GameOver. Quyền nhận Team soi của Seer và đồng đội Sói là ngoại lệ **riêng tư có giới hạn**, không biến Role thành public.
- **REV-02 [L,S]:** Khi bất cứ Player nào chuyển `Alive -> Dead` vì Sói, Witch, Voting hoặc Hunter Shot, event công khai `PlayerDied` (hoặc alias tương thích) **chỉ** cho biết PlayerId, trạng thái Dead và thông tin công khai cần thiết. **Không được chứa `Role`, `Team`, dữ liệu kỹ năng hoặc nguyên nhân bí mật có thể tiết lộ vai.** UI làm tối ô và hiện dấu ✕.
- **REV-03 [L,S]:** Trong resolve Night/Voting có Hunter pending, hoàn thành các death effects theo RES/HUN trước khi kết luận thắng; mỗi player chuyển Dead tối đa một lần và thông báo chết không lặp. Server được phép cập nhật trạng thái Dead hợp lệ nhưng **không** phát công khai vai khi chết.
- **REV-04 [L]:** Public event, public player view, room snapshot, reconnect replay và log công khai trong trận **không** có Role/Team của player khác, kể cả Dead. Trước GameOver không cung cấp danh sách full GameState có role. Client chỉ được thấy Role của mình và thông tin private đã được cấp quyền.
- **REV-05 [L,S]:** Khi `GameOver` đã được xác nhận sau toàn bộ Hunter effects, bắt buộc công bố Winner/Draw và phát `GameRolesRevealed` gồm **đầy đủ danh sách vai thật của tất cả player**. GameOver snapshot/reconnect phải chứa thông tin này để người vào lại vẫn xem kết quả.
- **REV-06 [K]:** `PlayerDied` và `GameRolesRevealed` là thông báo về trạng thái/thông tin, không gây thêm lượt chết, không hồi sinh, không làm thay đổi điều kiện thắng; không cho người Dead hành động thường.

**Specification REV:**

| Phần | Hợp đồng chính xác |
|---|---|
| Precondition (death) | Một Player chuyển Alive→Dead hợp lệ trong Night/Voting/Hunter processing |
| Input | `newlyDead :: [PlayerId]`, tính từ trạng thái server-side; không tin Client |
| Processing | Gộp distinct PlayerId, cập nhật LifeStatus và sinh `PlayerDied` public (không Role/Team); xử lý Hunter trước khi checkWin |
| Output trước GameOver | `PlayerDied {playerId, status=Dead}`; public player views cập nhật Dead/✕ |
| Output tại GameOver | `GameEnded` + `GameRolesRevealed {players: [{playerId, role, team}, ...]}` được định tuyến Public đúng thời điểm |
| Postcondition | Không phát lặp death event; secrecy cho tất cả Role đến GameOver; reveal không mutate gameplay |
| Error | Client xin Role người khác trước GameOver ⇒ `NotAuthorized`; không reveal thủ công từ Client |

**Pattern Cases REV:**

| Loại | Tình huống | Kết quả mong đợi |
|---|---|---|
| Happy | Seer bị Sói giết, không cứu | Sang Day người đó có ✕/Dead; **không** công khai Seer/Village |
| Happy | Werewolf bị Vote loại | Public Dead/✕; **không** công khai Werewolf/Wolves |
| Happy | Witch Poison Villager | Public Dead; không công khai Villager hoặc người dùng Poison |
| Edge | Hunter bị Vote, bắn Witch | Hai người Dead riêng, không lộ vai; Hunter resolve xong mới checkWin |
| Edge | Cùng một người bị 2 nguồn gây chết | Một `PlayerDied`, không trùng |
| Edge | Guard cứu A khỏi Wolf Kill | A Alive, không có `PlayerDied` |
| Edge | GameOver sau Hunter shot | Reveal **toàn bộ** role chỉ sau Hunter xử lý và GameOver |
| Edge | Reconnect giữa trận sau khi một người chết | History, snapshot và event replay không chứa Role/Team người chết |
| Error | Client đọc vai người khác trước GameOver | `NotAuthorized`; không leak qua event/chat/log |

**Chỉ dẫn tích hợp:** T01 chốt quy tắc; T02 định nghĩa type/event; T05 điều chỉnh domain death/resolve; T08 định tuyến/ẩn payload; T10 render dấu ✕; T11/T12 kiểm thử privacy và reconnect.

**[S] Protocol bắt buộc:** `type`, `requestId`, `gameId`, `gameVersion`; Domain events có `sequenceNumber`. Request trùng trong cùng session/game trả receipt trước hoặc `DuplicateRequest`, **không** nhân đôi action/death/event. Không dùng gameVersion do client tự khai để ghi đè state.

**[S] Reconnect:** disconnect ≠ chết; Client `lastSequence` → server trả event còn thiếu hoặc permission-filtered snapshot, không tạo ID mới; không gửi bí mật người khác, bao gồm cả Role người đã chết trước GameOver và mọi chat Sói không đủ quyền. Snapshot sau reconnect giữ nguyên vote đã nhận, potion đã tiêu, pending Hunter và lịch sử chat cùng ván đúng phòng/kênh/ngày. GameOver snapshot phải có full reveal.

**[S] Reliability:** `TVar GameState` + `atomically`/serialized GameLoop, `TQueue`/`TChan`, bounded queue/backpressure (`TBQueue`), supervision/cleanup, structured logs không chứa secret. Game server là authoritative; web client chỉ gửi intent. Domain pure, clock/RNG injected; event redaction và gửi tới đúng recipient tại server.

**[S] End-to-end trace:** `Browser -> JSON(Command) -> Protocol parse/auth -> Server -> applyCommand -> STM commit -> route Public/Private DomainEvent -> UI`. Các command invalid trả ErrorResponse, không emit giả. Các giá trị `gameVersion`/sequence tăng theo commit thành công; request replay idempotent không tạo commit thứ hai.

## 16. Các điểm còn thiếu: CHỐT MẶC ĐỊNH để nhóm sử dụng và biết rõ nguồn

**Quy tắc ưu tiên:** `[L]` = bản leader đã chốt (không sửa); `[S]` = Sheet hiện hành; `[T]` = bổ sung nhất quán với *The Werewolves of Miller’s Hollow / The Pact* (xem [R1]); `[K]` = quy ước thiết kế Server/Protocol, **không được gán là luật Ma Sói truyền thống**. `[P]` trong các mục trên chỉ tới mặc định chi tiết tại đây. Mọi dòng [T]/[K] là **phương án đã viết rõ để code/test thống nhất, chờ nhóm chính thức approve**. Nguồn truyền thống là tham khảo, không được dùng để ghi đè leader.

| ID | Mặc định chốt trong tài liệu | Nhãn nguồn | Lý do và điểm cần test |
|---|---|---|---|
| P01 | Host rời Lobby: chuyển Host cho người còn lại có thứ tự join sớm nhất; phòng trống xóa phòng | [K] | Đảm bảo luôn có quyền Start khi phòng không trống; test 1 người/Host rời |
| P02 | Tên hiển thị trim Unicode, không được rỗng; trùng tên trong cùng Lobby bị từ chối; PlayerId không trùng | [K] | Tránh nhầm mục tiêu trên UI; không biến tên thành định danh |
| P03 | Disconnect sau Start không giết/loại Player; reconnect bằng cùng PlayerId đã xác thực; thiếu action tới hạn => abstain/pass | [K] | Truyền mạng không thay đổi luật Alive; test reconnect voting |
| P04 | Mỗi actor một action/đêm; Wolf vote/Seer/Guard/Witch không được thay đổi một lựa chọn đã được chấp nhận | [K] | Ngăn race/đổi ý sau lộ thông tin; duplicate `requestId` không thực hiện lại |
| P05 | Alive hợp lệ tính tại đầu Night; hành động Night đã chấp nhận có hiệu lực tới cuối resolve dù actor chết trong cùng Night | [K] | Đồng thời/deterministic batch; Hunter vẫn là post-death effect |
| P06 | Night có substage: Wolf votes đóng → xác định victim → chỉ Witch nhận private `wolfVictim` hoặc `None` → Witch chọn Heal/Poison/Pass | [T] nguyên lý Witch biết người bị Sói chọn; [K] substages | Không gửi danh tính nạn nhân cho toàn phòng; test Heal khi tie/None |
| P07 | Guard không được bảo vệ cùng target ở **hai Night liền nhau**; nếu N2 Pass thì N3 được chọn lại target N1 | [T] không bảo vệ cùng người hai đêm liên tiếp; [K] semantics Pass | Vì N2 không có người được bảo vệ; test A/Pass/A hợp lệ |
| P08 | Witch Heal chỉ cần có `wolfVictim` (trước block Guard), nếu đồng thời Guard bảo vệ nạn nhân và Witch vẫn xác nhận Heal thì vẫn dùng hết thuốc; không hồi thuốc | [K] | Hai bảo vệ độc lập, tránh hoàn tác kỹ năng đã dùng; test guard + heal |
| P09 | `PlayerDied` PUBLIC chỉ có ID/Dead; **không** tiết lộ Role/Team khi chết; `GameRolesRevealed` chỉ tại GameOver | [L] + [S] cập nhật | Kiểm privacy cả Dead/Alive, reconnect và Hunter; thay mặc định [T] cũ |
| P10 | Chưa Vote tới hết hạn = abstain; không được đổi Vote; không ai Vote/hòa => không loại, không vote lại; thông tin phiếu cá nhân không public trước resolve | [L] hòa/không vote, [K] timeout/privacy | Bảo đảm không thể suy ngược lựa chọn cá nhân trước khi khóa |
| P11 | Hunter được bắn ở **pending shot substage** của Night/Voting dù actor đã Dead; timeout skip; pending xử lý trước checkWin | [L] nguyên nhân và quyền bắn, [K] substage | Có thể bắn Sói cuối cùng và chuyển kết quả sang Village hoặc Draw |
| P12 | Server điều khiển tick/transition. Cấu hình demo đề xuất: `Night action 90s`, `Witch decision 30s`, `Day 120s`, `Voting 60s`, `Hunter shot 30s`; cho phép cấu hình bằng settings (không hardcode Domain) | [K] | **Không phải thời gian từ sách**; test fake clock; thời hạn không tạo hành động tự động |
| P13 | Chat Day là event giao tiếp, không mutate gameplay GameState; chat history lưu ngoài game-state; text được trim/check nonempty | [L] + [K] nơi lưu | Pure engine không phải ghi mạng/chat database |
| P14 | Không Wolf vote hoặc hòa cao nhất ⇒ `wolfVictim = Nothing`; Witch Heal reject `NoWolfVictim`, không mất bình | [L] | 8 người Sói chia phiếu và 9 người ba phiếu khác nhau đều không cắn |
| P15 | Wolves nhận **danh sách Werewolf đồng đội qua private event khi Start**, không public; sói chết không nhận quyền action | [T] biết đồng đội, [K] event visibility | Test người thuộc Village không nhìn thấy wolves roster |
| P16 | Không có Role ngoài 6 role preset, không có Cupid/Lovers, Mayor, Little Girl, tie revote hay special neutral faction | [L] + [K] scope MVP | Không kéo thêm luật của *The Pact* vào project |
| P17 | Khi Night chỉ còn 1 Sói sống, 1 phiếu của Sói đó đủ quyết định victim; nếu không vote thì không cắn | [L] suy từ tally | Test cả 8/9 sau khi một số Sói chết |
| P18 | `GameEnded` công bố Winner/Draw và bắt buộc `GameRolesRevealed` cho **tất cả** Player ở GameOver; trước đó ẩn Role của cả Dead/Alive | [L] + [S] cập nhật | Snapshot/reconnect lọc theo recipient, GameOver mới full reveal |
| P19 | Nếu tất cả player chết cùng thời điểm, `Draw` **ưu tiên tuyệt đối**; không chốt thắng giữa pending shot, dù tại một thời điểm tạm `wolvesAlive >= villageAlive` | [L] | Test Hunter chết cùng Sói cuối; cả hai bằng 0 sau shot |
| P20 | Nếu Witch Heal đang được yêu cầu nhưng không có wolfVictim, trả `NoWolfVictim` và cho Witch tiếp tục chọn **một** hành động hợp lệ trong cửa sổ còn mở; action lỗi không tính lượt | [K] kết quả validation | Test invalid Heal → Poison (đúng cùng Night, nhưng chỉ Poison được chấp nhận) |

### 16.1. Các khác biệt CỐ Ý với luật truyền thống (không được "sửa" ngược)

| Vấn đề | Một số bản Ma Sói truyền thống | Chốt từ leader [L] |
|---|---|---|
| Witch dùng hai bình cùng đêm | *The Pact* có phiên bản cho dùng cả hai | **Chỉ Heal HOẶC Poison HOẶC Pass** một đêm |
| Hunter chết vì Poison | Điều kiện kích hoạt tùy phiên bản, có bản loại trừ | **Bất kỳ Alive→Dead đều có quyền bắn** |
| Hòa phiếu Ban ngày | Các biến thể dùng bầu lại hoặc luật đặc biệt | **Không ai chết, không vote lại** |
| Cơ chế Wolves | Sách thường nhắm nạn nhân theo đồng thuận | **Mỗi Sói chọn một Village Alive; đa số duy nhất, hòa thì không cắn** |
| Điều kiện thắng | Có nhiều biến thể thắng khi hết một phe | **Draw trước, hết Sói thì Village, Sói ≥ Dân thì Wolves** |

### 16.2. Ghi nguồn rõ ràng để nhóm review

- **[R1]** Philippe des Pallières & Hervé Marly, *The Werewolves of Miller’s Hollow: The Pact* (rulebook, Asmodee). Trang giới thiệu và tải rulebook: https://www.asmodee.ca/en/product/werewolves-of-millers-hollow-the-the-pact/ ; bản PDF: https://cdn.svc.asmodee.net/production-asmodeeca/uploads/2023/07/WerewolvesThePact_EN_Rules.pdf . Dùng để tham khảo **hành động theo đêm, Seer, Defender, Witch, Hunter và việc loại người/chia thông tin**. Không lấy các phần vai mở rộng.
- **[R2]** *The Werewolves of Miller’s Hollow* bản luật cơ bản, thư mục rulebook: https://en.1jour-1jeu.com/cardgame/2001-the-werewolves-of-millers-hollow/files . Đối chiếu mô hình Moderator điều phối Night/Day, Role ẩn và loại người.
- **[R3]** *The Werewolves of Miller’s Hollow — Official Rulebook* (Zygomatic): https://www.zygomatic-games.com/wp-content/uploads/2020/04/werewolvesofmillershollow_en_rules_compressed.pdf ; phần công bố người bị loại và lật lá vai. Bản diễn giải dễ tra cứu: https://www.ultraboardgames.com/the-werewolves-of-millers-hollow/game-rules.php . **Chỉ tham khảo luật truyền thống; dự án KHÔNG áp dụng công khai Role khi chết theo yêu cầu Leader mới.**
- **[L]** Leader, "CHỐT LUẬT T01 – BẢN ĐƠN GIẢN", được gửi trực tiếp trong nhóm: **nguồn quyết định ưu tiên cao nhất**, không phải tài liệu trên web.
- **[S]** Workbook `LTH_Đồ án Ma Sói.xlsx`, sheet `02 - WORKFLOW & TASK`, `03 - LUẬT & THIẾT KẾ`, `05 - TEST DEMO NỘP`: nguồn về kiến trúc, bảo mật, hợp đồng Domain và test.
- **[K]** Quy ước kỹ thuật của project do người soạn bổ sung để loại bỏ ambiguity, **không trích dẫn sai thành luật dân gian**. Đặc biệt timeout, duplicate request, Host succession, chat storage, substage protocol và thời lượng là quyết định thiết kế cần nhóm thông qua trước khi merge.

### 16.3. Quy trình thay đổi

Mọi thay đổi mặc định [T]/[K] phải ghi rõ `rule ID → lý do → ảnh hưởng Domain/Protocol/Frontend → test thay đổi → người duyệt`. Nếu nhóm bác bỏ một mặc định, sửa **đặc tả và test trước khi code**, không để phần code tự tạo biến thể luật. Mục 16 là **bản luật hoàn thiện đề xuất chính thức cho review**, chưa khẳng định đã được leader phê duyệt.

## 17. Acceptance tests — happy/error/edge bắt buộc

| ID | Loại | Given / When | Expected |
|---|---|---|---|
| T01-CFG-H1 | Happy | 8 Ready, Host Start, preset 2 Wolves | Night, 8 role assignment |
| T01-CFG-H2 | Happy | 9 Ready, Host Start, preset 3 Wolves | Night, 9 role assignment |
| T01-CFG-E1 | Error | 8 Player + 3 Wolves | InvalidConfiguration, state unchanged |
| T01-CFG-X1 | Edge | 7/10 người Start | InvalidPlayerCount |
| T01-LOB-H1 | Happy | Join, Ready tất cả, Host Start | PlayerJoined/ReadyChanged/GameStarted |
| T01-LOB-E1 | Error | Không phải Host Start | NotAuthorized |
| T01-LOB-X1 | Edge | Start và Unready đồng thời | Atomic, không start nếu state mới NotReady |
| T01-PHS-H1 | Happy | Night resolve không thắng | Day, sau đó Voting |
| T01-PHS-E1 | Error | Vote trong Night | WrongPhase |
| T01-PHS-X1 | Edge | Hết sống sau Night | GameOver Draw, không vào Day |
| T01-WOL-H1 | Happy | 3 Sói: A,A,B | wolfVictim A |
| T01-WOL-E1 | Error | Sói chọn Sói | InvalidTarget |
| T01-WOL-X1 | Edge | 2 Sói: A,B / 3 Sói: A,B,C | Tie => no kill |
| T01-SEE-H1 | Happy | Seer xem Sói | Private Wolves |
| T01-SEE-E1 | Error | Seer tự xem | InvalidTarget |
| T01-SEE-X1 | Edge | Seer xem Guard | Private Village, no leak |
| T01-GRD-H1 | Happy | Guard tự bảo vệ | Block Wolves targeting self |
| T01-GRD-E1 | Error | Guard chọn target N1 và N2 giống nhau | ConsecutiveGuardTarget |
| T01-GRD-X1 | Edge | Guard bảo vệ mục tiêu trúng Poison | Poison vẫn giết |
| T01-WIT-H1 | Happy | Wolves target A, Witch Heal | A survives Wolves |
| T01-WIT-E1 | Error | Heal khi không wolf victim | NoWolfVictim, potion retained |
| T01-WIT-X1 | Edge | Witch bị Wolves nhắm, Heal self | Witch lives |
| T01-WIT-X2 | Edge | Guard block attack, Witch Poison cùng target | Target chết bởi Poison |
| T01-WIT-E2 | Error | Witch dùng Heal + Poison cùng Night | MultipleWitchActions |
| T01-HUN-H1 | Happy | Hunter chết do Vote, bắn A | A dies before checkWin |
| T01-HUN-E1 | Error | Hunter bắn dead target hoặc bắn lần 2 | Left, no extra death |
| T01-HUN-X1 | Edge | Hunter chết do Poison | Được kích hoạt shot |
| T01-HUN-X2 | Edge | Hunter timeout | Skip, then checkWin |
| T01-DAY-H1 | Happy | Alive Chat ở Day | ChatMessage, game state unchanged |
| T01-DAY-E1 | Error | Chat chỉ whitespace | EmptyChat |
| T01-DAY-X1 | Edge | Dead Chat; Villager chat Night; Wolf Alive chat WolvesNight | DeadPlayer; WrongPhase/NotAuthorized; WolvesNight được phép cho Wolf Alive |
| T01-CHAT-H2 | Happy | Wolf Alive gửi WolvesNight trong Night | Chỉ Wolves Alive được quyền nhận; không đổi gameplay state |
| T01-CHAT-E2 | Error | Villager/Dead gửi hoặc đọc WolvesNight | `NotAuthorized` / `DeadPlayer`, không lộ history |
| T01-CHAT-X2 | Edge | Tin PublicDay ngày 1/2, reconnect cùng game | Khôi phục đủ lịch sử đúng ngày/kênh/room, theo sequence |
| T01-REV-H1 | Happy | Alive→Dead trong Night/Voting | Public `PlayerDied` ID/Dead; không chứa Role/Team |
| T01-REV-H2 | Happy | GameOver sau Hunter | `GameRolesRevealed` đủ mọi Player, gồm Alive/Dead |
| T01-REV-E1 | Error | Xin vai Dead trước GameOver | NotAuthorized, snapshot/replay không lộ |
| T01-UI-H1 | Happy | 8 người, Dashboard 9 ô | 8 ô player + 1 ô `Đang chờ`, xuyên pha |
| T01-UI-X1 | Edge | Chọn target bất hợp lệ trên UI/forged request | UI khóa/giải thích; server trả InvalidTarget, state không đổi |
| T01-VOT-H1 | Happy | Một người cao phiếu duy nhất | Eliminated + hunter + win |
| T01-VOT-E1 | Error | Vote 2 lần hoặc self-vote | AlreadyVoted / InvalidTarget |
| T01-VOT-X1 | Edge | Hòa hoặc không phiếu | No elimination; no revote |
| T01-WIN-H1 | Happy | 0 Wolves, 1 Village alive | Winner Village |
| T01-WIN-E1 | Error | Client ép GameEnded | NotAuthorized |
| T01-WIN-X1 | Edge | 0 Wolves, 0 Village | Draw |
| T01-WIN-X2 | Edge | 1 Wolves, 1 Village | Winner Wolves |
| T01-ENG-H1 | Happy | Valid command | Right, state/events deterministic |
| T01-ENG-E1 | Error | Invalid command | Left, no commit/events |
| T01-ENG-X1 | Edge | 2 concurrent votes / duplicate requestId | No lost update / no duplicate effect |
| T01-PRIV-X1 | Edge | Seer result, role assignment, witch notice, người chết | Private đúng recipient; public/reconnect **không** lộ Role/Team bất kỳ người nào trước GameOver |
| T01-INT-H1 | Integration | 8 Player Join→Night→Day→Voting→Night | Phases/events consistent |
| T01-INT-H2 | Integration | 9 Player, Hunter chain→Draw/GameOver | Correct priority/events/privacy |

**[S] Mức test tối thiểu của toàn dự án theo Sheet `05 - TEST DEMO NỘP`:** ≥14 unit tests; ≥3 property tests × 100 samples; ≥2 integration tests. Ma trận trên rộng hơn mức tối thiểu để T01 có acceptance criteria theo từng rule; implement chủ yếu thuộc các task T02–T12.

**Property đặc biệt:** (1) ID duy nhất; (2) accepted command giữ invariants; (3) command sai không commit; (4) một Player không chết hai lần; (5) role preset đúng 8/9; (6) public event không lộ Role/Team của bất kỳ Player nào trước GameOver; GameOver reveal đủ 8/9 vai; (7) replay cùng seed/commands/timer cho cùng outcome.

## 18. Trace mẫu 8 người / 9 người và biến cố hiếm

**8 người:** `W1 W2 S G Wi H V1 V2` đều Ready → Host Start → Night1: W1→V1, W2→V2 (hòa, không Sói chết ai); G→G; S→W1 (private Wolves); Wi Pass → Day không ai chết → Voting hai phe bỏ phiếu hòa → Night2. Không có revote.

**9 người:** `W1 W2 W3 S G Wi H V1 V2` Ready → Night1: W1/W2→H, W3→V1, G→V2, Wi Pass → H chết → Pending Hunter Shot H→W1 ⇒ W1 chết → kiểm thắng với 2 Sói và 5 dân còn sống (sau H chết) ⇒ Continue Day. Nếu Witch Poison H trong cùng đêm, H vẫn chết chỉ một lần, bắn một lần.

**Đặc biệt — tất cả chết:** Trước Hunter Shot chỉ còn Hunter và Wolf; Wolf Kill Hunter hợp lệ → Hunter Dead, chưa checkWin; Hunter bắn Wolf còn Alive → cả hai hết sống → `Draw`, không tính Village vì wolvesAlive==0.

**Đặc biệt — Witch Heal lỗi:** 8 người, W1→V1, W2→V2 ⇒ hòa ⇒ `wolfVictim=None`; Witch Heal ⇒ `NoWolfVictim` và potion vẫn còn; Witch có thể chọn Poison hoặc Pass **nếu** cơ chế action còn mở và trước đó Heal bị từ chối [P].

## 19. Mapping task, review và definition of done

| Task | Dựa vào mục | Output/kỳ vọng |
|---|---|---|
| T01 — TV1 | Toàn tài liệu | `docs/game-rules.md`; không mâu thuẫn leader/sheet; có happy/error/edge |
| T02 — TV1 | 2–5, 14 | ADT Role/Team/Phase/Player/GameState/Command/Event/Error; validation + invariant |
| T03 | 3, 14–15 | Join/Leave/Ready + Server/Protocol events |
| T04 | 4, 10, 13 | Phase engine, Start, deterministic transitions |
| T05 | 5–11 | Night rules, potion, guard history, pending Hunter |
| T06 | 12–13 | Vote, tie/no-vote, lynch, hunter, win |
| T07 | 12–13, 15 | Chat/result, public/private payload |
| T08–T12 | 14–18 | STM/server/frontend integration, replay, privacy, tests |

**Review bắt buộc:** TV2 duyệt Protocol/Event, staged Witch notice, idempotency; TV5 duyệt testability, timeout/pending Hunter, happy/error/edge; leader phê duyệt các mặc định [T]/[K] ở mục 16. **Chỉ sau phê duyệt và cập nhật code/test tương ứng.**

## 20. Yêu cầu giao diện và tích hợp bổ sung — UI / Dashboard / Chat / Privacy (14/10/2026)

> **Phạm vi:** Mục này là hợp đồng nghiệp vụ/acceptance cho các task T02, T03, T05–T12. Không yêu cầu TV1 tự triển khai toàn bộ Frontend; owner từng module thực hiện theo Excel. **Không thay đổi** preset, khả năng vai, luật WOL-02, Voting ban ngày hay Win Condition.

- **UI-01 [L,S] — Dashboard 3×3:** Sau khi tạo/tham gia phòng, Dashboard có **9 ô vuông** bố trí **3 hàng × 3 cột**; mỗi người một ô hiển thị tên, Appearance và trạng thái. Phòng 8 người có 1 ô `Đang chờ`. Dashboard duy trì xuyên Night, Day, Voting và GameOver, không dựng lại theo kiểu làm mất player context.
- **UI-02 [L,S] — Appearance:** Chọn preset ngoại hình/trang phục **trước Join/Create**, Server xác minh preset hợp lệ và đồng bộ Appearance công khai qua roster/PlayerView cho cả phòng. Appearance không mã hóa Role và không cấp quyền game.
- **UI-03 [L,S] — Role/Ability riêng:** Sau Start, chỉ chủ sở hữu thấy tên Role và nút `Khả năng của tôi` dưới ô của mình. Nút mở panel hướng dẫn **role làm gì, phase hành động, target hợp lệ, giới hạn sử dụng**, không tự gửi command. Mọi payload gửi cho người khác phải bỏ Role/Ability riêng.
- **UI-04 [L,S] — Chọn mục tiêu tại ô:** Trong Night Action hoặc Voting, chỉ ô người Alive và target hợp lệ mới chọn được; ô không hợp lệ bị khóa và hiện lời giải thích ngắn. Người chơi xác nhận trước khi gửi; Server **kiểm tra lại** actor, phase, role, Alive, target và lượt/ability. Không dựa vào button disabled để đảm bảo an toàn.
- **UI-05 [L,S] — Sói riêng tư:** Sói Alive dùng `WolvesNight` và xem tiến độ chọn của đồng đội theo WOL-02/WOL-04. Đóng vote khi đủ Sói sống hoặc hết cửa sổ vote, tally theo **phiếu cao nhất duy nhất**; ví dụ 3 Sói A–A–B ⇒ A; A–B–C ⇒ không cắn. Không gửi chat/tiến độ/target Sói cho Village.
- **UI-06 [L,S] — Chat Day/history:** Khung chat chung bên **trái Dashboard**; Alive mới gửi `PublicDay` trong Day. Có mốc `Ngày N bắt đầu`, giữ lịch sử qua ngày và reconnect/reload trong cùng ván. History tách theo game/room/channel/day và sequence; không trộn PublicDay với WolvesNight.
- **UI-07 [L,S] — Bubble:** Mỗi tin mới làm xuất hiện bong bóng trên ô người gửi **3–5 giây**, tin dài rút gọn; bong bóng biến mất không xóa tin trong chat history. Bong bóng WolvesNight chỉ được render cho recipient có quyền.
- **UI-08 [L,S] — Dead state:** Khi Dead, ô tối và phủ ✕; không chat/vote/target theo luật (ngoại lệ pending Hunter Shot theo HUN). Trước GameOver chỉ công khai trạng thái chết, **không Role/Team**.
- **UI-09 [L,S] — GameOver:** Hiển thị Winner Village/Wolves hoặc Draw, danh sách toàn bộ người chơi và Role thật; chỉ thực hiện full reveal tại GameOver, bao gồm reconnect/snapshot cuối trận.
- **UI-10 [L,S] — Hướng dẫn:** Nút `?` hoặc `⋯` trên đầu màn hình mở bảng hướng dẫn Join/Create, thứ tự Night→Day→Voting, chọn target, điều kiện thắng, vai nói chung; không lộ danh tính–Role trong ván. Có nút đóng, hỗ trợ bàn phím và điện thoại.

### 20.1. Data contracts cần chốt theo task

| Contract | Nội dung tối thiểu | Owner triển khai/tiêu thụ |
|---|---|---|
| `Appearance` | Preset ID/giá trị trong allowlist, đồng bộ public | T02 → T03/T10 |
| `PlayerView` public | playerId, displayName, ready, alive/dead, appearance; **không role/team** | T02 → T03/T08/T10 |
| `RoleAbilityInfo` | Role và mô tả riêng cho chủ sở hữu | T02/T07 → T10 |
| Valid targets | List/điều kiện cho actor+phase+action; Server revalidate | T05/T02 → T08/T10 |
| `ChatChannel`, `ChatRecord` | `PublicDay`/`WolvesNight`, roomId, day, channel, messageId, sequence, senderId, text | T02/T07 → T08/T09/T10 |
| `EventVisibility` | `Public`, `Private`, `TeamOnly`; Server-side recipient filter | T02 → T08 |
| Death/reveal | `PlayerDied` trước GameOver; `GameRolesRevealed` chỉ GameOver | T02/T05/T06 → T08/T10 |
| Wolf progress | `WolfVoteUpdated`/`WolfTargetLocked` TeamOnly | T05 → T08/T10 |

### 20.2. Ranh giới triển khai và xác nhận

1. **TV1 (T01/T02/T05):** Chốt luật/Domain ADTs, validation, night target/vote contract, không reveal trước GameOver; bổ sung unit tests phần thuộc sở hữu.
2. **TV2 (T08/T12):** STM, WebSocket routing, permission-filtered snapshot/replay, broadcast đúng Public/Private/TeamOnly; phối hợp tích hợp.
3. **TV3 (T03/T10):** Dashboard 9 ô, preset Appearance, Role button, target-selection UI, Dead overlay, responsive.
4. **TV4 (T07):** Chat protocol/lịch sử/phân quyền, guide/FAQ theo task phân công.
5. **TV5 (T06/T09/T11):** Voting/Hunter, reconnect và bộ test hội nhập theo phân công.
6. **Trạng thái triển khai:** Nội dung mục 20 là **đặc tả**, không phải bằng chứng source đã có đầy đủ. Mọi thay đổi Domain Event/JSON contract cần được đồng bộ qua PR và giữ compatibility hoặc cập nhật tất cả consumer/test cùng lúc.

### 20.3. Kiểm thử nghiệm thu bổ sung

- 8 người ⇒ 9 ô, 1 ô `Đang chờ`; 9 người ⇒ đủ 9 ô; dashboard không biến mất khi đổi phase.
- Appearance bất hợp lệ bị từ chối; preset hợp lệ hiển thị giống nhau trên mọi client.
- Browser A không nhận Role/Ability của B trước GameOver, kể cả khi B đã chết hoặc A reconnect.
- Nhấn `Khả năng của tôi` không tạo Domain action; Server từ chối forged target.
- Sói A–A–B ⇒ A; A–B–C ⇒ không có wolfVictim; WolfsOnly history/progress không rò ra Village.
- Alive PublicDay chat hợp lệ; Dead/Villager trong WolvesNight bị từ chối; history giữ qua Day 1/2/reconnect cùng ván.
- Bubble tự ẩn sau 3–5 giây; record vẫn còn trong chat; bubble sói không xuất hiện bên ngoài phe.
- Night/Voting/Hunter Death ⇒ public chỉ ID/Dead, không Role; GameOver reveal **đủ** 8/9 role.
- Guide mở/đóng bằng click và bàn phím, dùng được trên mobile, không lộ dữ liệu vai hiện tại.

**Thay đổi so với bản luật trước:** bỏ quy tắc [T] lật vai người chết; thêm hai kênh chat; mở rộng event visibility; giữ nguyên luật Sói theo Excel; thêm đặc tả Dashboard/UI để T02–T12 triển khai và kiểm thử thống nhất.
