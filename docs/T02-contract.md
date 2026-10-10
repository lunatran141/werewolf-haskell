# T02 – DOMAIN TYPES & VALIDATION CONTRACT

**Dự án:** Werewolf Haskell
**Task:** T02 – Domain Types & Validation
**Owner:** TV1
**Tài liệu luật tham chiếu:** `docs/game-rules.md` (v4.0)
**Phạm vi:** Domain Types, Smart Constructor, Validation, GameState Invariant và hợp đồng tích hợp chung.

## 1. Mục tiêu

Task T02 xây dựng nền tảng kiểu dữ liệu và các hàm kiểm tra tính hợp lệ cho trò chơi Ma Sói, bảo đảm những module khác trong hệ thống sử dụng chung một cấu trúc dữ liệu và quy tắc validation.

T02 tập trung vào các nguyên tắc lập trình hàm:

- **Algebraic Data Types (ADT):** Biểu diễn Role, Team, Phase, Command, DomainEvent và GameError.
- **Record:** Biểu diễn Player, GameState và các dữ liệu liên quan.
- **Pattern Matching:** Phân biệt Role, Phase, trạng thái sống/chết và hành động.
- **Maybe:** Biểu diễn Role chưa được phân, mục tiêu tùy chọn và kết quả chưa xác định.
- **Either:** Trả về kết quả hợp lệ hoặc GameError khi validation thất bại.
- **Pure Function:** Các hàm validation không thực hiện IO hoặc thay đổi GameState.

## 2. Phân chia trách nhiệm

| Task              | Trách nhiệm                                                                   |
| ----------------- | ----------------------------------------------------------------------------- |
| T01               | Đặc tả luật chơi, Role, Phase, Night Action, Vote, Win Condition và Edge Case |
| T02               | Khai báo Domain Types, Smart Constructor, Validation và GameState Invariant   |
| T03               | Xử lý Lobby: Join, Leave, Ready, chuyển Host và Lobby Events                  |
| Các task Gameplay | Thực thi StartGame, Night Action, Voting, Hunter và Win Condition             |
| Protocol/Server   | Xác thực phiên, JSON, WebSocket, timeout, reconnect và đồng bộ trạng thái     |

T02 chỉ định nghĩa dữ liệu và điều kiện hợp lệ. Việc cập nhật GameState, thực thi Command và phát DomainEvent thuộc về các task triển khai tương ứng.

## 3. Contract kiểu dữ liệu

### 3.1. Role và Team

`Role` bao gồm:

- `Werewolf`
- `Seer`
- `Guard`
- `Witch`
- `Hunter`
- `Villager`

`Team` bao gồm:

- `Wolves`
- `Village`

Quy tắc ánh xạ:

- `Werewolf` thuộc `Wolves`.
- Các Role còn lại thuộc `Village`.

### 3.2. Phase

Các Phase nghiệp vụ:

`Lobby → Night → Day → Voting → Night`

Khi trò chơi kết thúc, Phase chuyển sang `GameOver`.

`GameOver` là trạng thái kết thúc, không được tiếp tục nhận Command Gameplay.

### 3.3. Player

Mỗi Player bao gồm:

| Trường             | Kiểu         | Ý nghĩa             |
| ------------------ | ------------ | ------------------- |
| `playerId`         | `PlayerId`   | Định danh duy nhất  |
| `playerName`       | `String`     | Tên hiển thị        |
| `playerRole`       | `Maybe Role` | Vai trò được phân   |
| `playerReady`      | `Bool`       | Trạng thái sẵn sàng |
| `playerLifeStatus` | `LifeStatus` | Alive hoặc Dead     |

Trong Lobby, `playerRole = Nothing`.

Sau StartGame, mỗi Player phải có một Role hợp lệ.

PlayerId được sử dụng làm định danh nghiệp vụ; không dùng tên người chơi thay cho PlayerId.

### 3.4. GameState

GameState lưu trạng thái nghiệp vụ của một ván chơi:

- Danh sách người chơi và Host.
- Phase hiện tại.
- Số lượt/ngày hiện tại.
- Cấu hình phân vai.
- Danh sách Night Actions và Votes.
- Trạng thái Potion của Witch.
- Mục tiêu Guard đã bảo vệ trong đêm trước.
- Trạng thái Hunter đang chờ bắn.
- Danh sách Role Reveal đang chờ.
- Kết quả ván chơi.

Các module khác không được tự tạo trạng thái trái với GameState Invariant.

### 3.5. GameResult

GameResult gồm:

- `Winner Wolves`
- `Winner Village`
- `Draw`

`Nothing :: Maybe GameResult` biểu diễn chưa có kết quả cuối cùng.

Phân biệt rõ `Draw` và trạng thái trò chơi đang tiếp tục.

### 3.6. Command

Các Command dùng chung:

- `Join`
- `Leave`
- `SetReady`
- `StartGame`
- `AdvancePhase`
- `NightAction`
- `Vote`
- `Chat`
- `ResolveNight`
- `ResolveVoting`
- `ResolveHunter`

T02 khai báo Command; module thực thi có trách nhiệm cập nhật GameState và phát Event.

Các Command nội bộ như `AdvancePhase`, `ResolveNight`, `ResolveVoting` chỉ được Server thực hiện sau khi kiểm tra quyền.

### 3.7. DomainEvent

DomainEvent thông báo kết quả xử lý Command.

Các sự kiện quan trọng gồm:

- `PlayerJoined`
- `PlayerJoinedDetailed`
- `PlayerLeft`
- `HostChanged`
- `ReadyChanged`
- `GameStarted`
- `PhaseChanged`
- `PlayerRoleAssigned`
- `NightActionAccepted`
- `SeerResult`
- `VoteUpdated`
- `PlayerEliminated`
- `PlayerRoleRevealed`
- `HunterShotPending`
- `HunterShotResolved`
- `GameFinished`
- `ChatMessage`

Server chịu trách nhiệm gửi Event đến đúng đối tượng nhận.

Thông tin Role của người còn sống và kết quả soi của Seer phải được giữ riêng tư.

Theo luật, PlayerRoleAssigned, SeerResult, NightActionAccepted, VoteUpdated và HunterShotPending được xử lý là Private Event. Các thông tin Role của người sống không được công khai. PlayerRoleRevealed chỉ được phát công khai sau khi người chơi chết và các Death Effects liên quan đã được xử lý. Nếu cần công bố tiến độ Voting, module Voting phải sử dụng sự kiện tổng hợp không tiết lộ lựa chọn cá nhân.

## 4. Contract Smart Constructor

### 4.1. `mkPlayer`

Chữ ký:

`mkPlayer :: PlayerId -> String -> Either GameError Player`

Điều kiện:

- PlayerId không được rỗng hoặc chỉ có khoảng trắng.
- PlayerName không được rỗng hoặc chỉ có khoảng trắng.
- Tên được chuẩn hóa khoảng trắng.

Giá trị mặc định:

- `playerRole = Nothing`
- `playerReady = False`
- `playerLifeStatus = Alive`

### 4.2. Chuẩn hóa tên người chơi

`normalizePlayerName` loại bỏ khoảng trắng thừa ở đầu/cuối và rút gọn khoảng trắng giữa các từ.

Ví dụ:

- `"  Vân  "` → `"Vân"`
- `"Nguyễn   Văn   A"` → `"Nguyễn Văn A"`

`playerNameKey` dùng để so sánh tên không phân biệt chữ hoa/thường trong phạm vi hỗ trợ của `Data.Char.toLower`.

Hai người chơi không được sử dụng tên trùng sau chuẩn hóa.

## 5. Contract Validation

| Hàm                         | Điều kiện cần kiểm tra                                     |
| --------------------------- | ---------------------------------------------------------- |
| `validateUniquePlayerIds`   | PlayerId không trùng                                       |
| `validateUniquePlayerNames` | Tên không trùng sau chuẩn hóa                              |
| `validatePlayerCount`       | Có chính xác 8 hoặc 9 người khi Start                      |
| `validateRolePreset`        | Đúng số lượng từng Role                                    |
| `validateJoin`              | Đang ở Lobby, phòng chưa đầy, ID và tên không trùng        |
| `validateLeave`             | Đang ở Lobby, Player tồn tại                               |
| `validateSetReady`          | Đang ở Lobby, Player tồn tại                               |
| `validateStartGame`         | Đúng Host, đủ người, tất cả Ready và preset hợp lệ         |
| `validateNightAction`       | Đúng Phase, Role, mục tiêu và giới hạn khả năng            |
| `validateVote`              | Đang Voting, Player còn sống, mục tiêu hợp lệ và chưa Vote |
| `validateChat`              | Đang Day, Player còn sống, nội dung không rỗng             |
| `validateHunterShot`        | Hunter đã chết, đang chờ bắn, target hợp lệ                |
| `validateGameInvariant`     | GameState nhất quán theo các điều kiện bất biến            |

Validation trả `Left GameError` nếu không hợp lệ.

Validation không được trực tiếp thay đổi GameState.

## 6. Cấu hình Role

### Ván 8 người

| Role     | Số lượng |
| -------- | -------: |
| Werewolf |        2 |
| Seer     |        1 |
| Guard    |        1 |
| Witch    |        1 |
| Hunter   |        1 |
| Villager |        2 |

### Ván 9 người

| Role     | Số lượng |
| -------- | -------: |
| Werewolf |        3 |
| Seer     |        1 |
| Guard    |        1 |
| Witch    |        1 |
| Hunter   |        1 |
| Villager |        2 |

`validateRolePreset` kiểm tra số lượng Role, không yêu cầu thứ tự danh sách giống nhau.

T02 không chịu trách nhiệm phân vai ngẫu nhiên.

## 7. GameState Invariant

Một GameState hợp lệ phải thỏa mãn:

1. Mọi PlayerId đều hợp lệ và duy nhất.
2. Tên người chơi không trùng sau chuẩn hóa.
3. Phòng không vượt quá 9 người.
4. Khi phòng rỗng, Host phải rỗng.
5. Khi phòng có người, Host phải thuộc danh sách Player.
6. Trong Lobby, Player chưa được phân Role và chưa có người chết.
7. Game đã bắt đầu phải có đúng 8 hoặc 9 người với preset hợp lệ.
8. Actor không được Vote hai lần trong một lượt.
9. Actor không được gửi hai Night Actions trong cùng lượt.
10. Votes đang chờ chỉ được tồn tại trong Phase Voting.
11. Night Actions đang chờ chỉ được tồn tại trong Phase Night.
12. Trong GameOver, phải có GameResult hợp lệ.
13. Khi game chưa kết thúc, GameResult phải là Nothing.
14. Hunter pending phải là Hunter đã chết và chưa sử dụng lượt bắn.
15. Chính sách hòa phải là NoElimination, không chọn người theo PlayerId.

Các module cập nhật GameState phải duy trì những invariant này.

## 8. Contract giữa T02 và T03 Lobby

T02 cung cấp:

- Player và GameState.
- Các Command `Join`, `Leave`, `SetReady`.
- Các Event phục vụ Lobby.
- Smart Constructor cho Player.
- Validation cho Join, Leave và Ready.
- Dữ liệu LobbyMember cho giao diện.

T03 chịu trách nhiệm:

- Thêm Player khi Join thành công.
- Xóa Player khi Leave hợp lệ.
- Gán người vào đầu tiên làm Host.
- Chuyển Host khi Host hiện tại rời phòng.
- Thay đổi trạng thái Ready.
- Chỉ phát ReadyChanged khi Ready thực sự thay đổi.
- Gửi Lobby State đến các Client.

Trạng thái Connected/Disconnected được Server xác nhận. Việc mất kết nối không đồng nghĩa với người chơi chết.

## 9. Contract luật Gameplay

### Night Actions

- Werewolf chỉ được chọn người còn sống thuộc Village.
- Seer không được soi chính mình.
- Guard được bảo vệ chính mình nhưng không được bảo vệ cùng một Player trong hai đêm liên tiếp.
- Witch có một Heal và một Poison cho cả game, tối đa một hành động trong một đêm.
- Heal chỉ áp dụng khi có nạn nhân do Werewolf tấn công hợp lệ.
- Poison không bị Guard hoặc Heal chặn.

### Voting

- Chỉ Player còn sống được Vote.
- Không được tự Vote.
- Không được Vote hai lần trong cùng lượt.
- Hòa cao nhất hoặc không có phiếu thì không ai bị loại.
- Không có vòng Vote lại.

### Hunter

- Hunter chết bởi bất kỳ nguyên nhân nào đều có thể kích hoạt Hunter Shot.
- Hunter có thể bắn một Player khác còn sống hoặc bỏ lượt.
- Hiệu ứng Hunter phải được xử lý trước khi kiểm tra kết quả cuối cùng.

### Win Condition

Kiểm tra theo đúng thứ tự:

1. Không còn Player sống → Draw.
2. Không còn Werewolf sống → Village thắng.
3. Số Werewolf sống lớn hơn hoặc bằng số Village sống → Wolves thắng.
4. Các trường hợp còn lại → Tiếp tục game.

T02 định nghĩa contract và validation. Việc giải quyết Night, Voting, Hunter và Win Condition thuộc các module gameplay tương ứng.

## 10. Unit Test và Property Test

### Unit Test

Kiểm thử các nhóm:

- Smart Constructor hợp lệ và không hợp lệ.
- PlayerId và PlayerName trùng.
- Preset Role 8/9 người.
- Điều kiện StartGame.
- Điều kiện Join/Leave/Ready.
- Night Action Validation.
- Vote và Chat Validation.
- GameState Invariant.
- Event Visibility.

Yêu cầu tối thiểu: **14 Unit Tests**.

### Property Test

Sử dụng QuickCheck, tối thiểu 100 mẫu cho mỗi Property.

Những tính chất cần kiểm tra:

1. Hoán vị danh sách Role hợp lệ không làm thay đổi tính hợp lệ của preset.
2. Smart Constructor tạo Player với các trường mặc định hợp lệ.
3. PlayerId bị trùng luôn bị từ chối.
4. GameState có Host không tồn tại trong danh sách Player bị từ chối.

Yêu cầu tối thiểu: **3 Property Tests**.

## 11. Tích hợp và thay đổi Contract

Các thành viên phải sử dụng kiểu dữ liệu chung từ `Domain.Types`.

Khi sửa constructor, Record hoặc chữ ký hàm, cần kiểm tra ảnh hưởng tới:

- `Domain.Rules`
- `Domain.Engine`
- `Protocol.Types`
- `Protocol.Json`
- `Server`
- Test suite

Không tự ý thay đổi luật đã chốt trong T01.

Các thay đổi contract ảnh hưởng đến module khác phải được trao đổi và review trước khi merge.

## 12. Tiêu chí hoàn thành T02

T02 được xem là hoàn thành khi:

- [ ] `src/Domain/Types.hs` khai báo đầy đủ Domain Types.
- [ ] `src/Domain/Validation.hs` có Smart Constructor và Validation.
- [ ] `validateGameInvariant` kiểm tra trạng thái nghiệp vụ nhất quán.
- [ ] `docs/T02-CONTRACT.md` thống nhất với code thực tế.
- [ ] Có tối thiểu 14 Unit Tests.
- [ ] Có tối thiểu 3 Property Tests, ít nhất 100 mẫu/test.
- [ ] `cabal build all` thành công.
- [ ] `cabal test all` thành công.
- [ ] Các module liên quan không bị lỗi do thay đổi Contract.
- [ ] Code và tài liệu được commit/push lên nhánh `feature/T02-domain-types-validation`.
- [ ] Pull Request được tạo hoặc cập nhật để nhóm review.

**Lưu ý:** Tài liệu này là hợp đồng chung của T02. Nếu tên constructor hoặc chữ ký hàm trong code hiện tại khác với tài liệu, cần đồng bộ chúng trước khi đánh dấu T02 hoàn thành.
