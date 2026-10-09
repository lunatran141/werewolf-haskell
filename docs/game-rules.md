# Game Rules – Werewolf Haskell

> **Trạng thái tài liệu:** Bản quy tắc chuẩn để nhóm review trước khi triển khai và kiểm thử.
>
> **Mục đích:** Là nguồn thống nhất giữa luật chơi, Domain, Validation, Protocol, Server, Frontend và Test.
>
> **Nguyên tắc:** Server là nơi xác thực luật và quyết định trạng thái game. Frontend chỉ gửi Command và hiển thị dữ liệu Server cho phép công khai hoặc gửi riêng.

## 1. Mục tiêu và nguyên tắc thiết kế

### 1.1. Mục tiêu

Xây dựng trò chơi Ma Sói trực tuyến cho 8–9 người chơi bằng Haskell, có giao diện trình duyệt và Server chịu trách nhiệm quản lý toàn bộ trạng thái game.

Hệ thống cần hỗ trợ:

* Tạo phòng, tham gia phòng, rời phòng và sẵn sàng.
* Bắt đầu game và phân vai.
* Luân phiên Night, Day và Voting.
* Xử lý hành động theo Role.
* Xác định người chết, điều kiện thắng và kết thúc game.
* Trao đổi dữ liệu Client–Server qua Protocol.
* Xử lý nhiều yêu cầu đồng thời mà không làm sai trạng thái.
* Bảo vệ thông tin Role và thông tin riêng của từng Player.
* Kiểm thử luật chơi độc lập với giao diện và kết nối mạng.

### 1.2. Nguyên tắc kiến trúc

1. **Server authoritative:** Server là nguồn sự thật duy nhất về GameState.
2. **Pure Core:** Logic luật chơi chính được triển khai bằng hàm thuần.
3. **Separation of concerns:** Tách Domain, Protocol, Server và Frontend.
4. **Validation:** Mọi Command phải được kiểm tra trước khi cập nhật trạng thái.
5. **Privacy:** Không gửi thông tin Role hoặc kết quả riêng cho người không có quyền nhận.
6. **Concurrency safety:** Các cập nhật trạng thái dùng cơ chế đồng bộ phù hợp, chẳng hạn STM.
7. **Testability:** Logic game phải có thể kiểm thử mà không cần chạy giao diện.
8. **Single source of truth:** Luật chính thức của Project nằm trong `docs/game-rules.md`.

### 1.3. Hàm xử lý luật cốt lõi

Hàm xử lý Command được định nghĩa theo kiểu:

```haskell
applyCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
```

Ý nghĩa:

* `GameState`: trạng thái trước khi xử lý.
* `Command`: yêu cầu do Player hoặc thành phần có quyền gửi.
* `Left GameError`: Command không hợp lệ; không tạo trạng thái game mới.
* `Right (newState, events)`: Command hợp lệ, trả về trạng thái mới và danh sách sự kiện phát sinh.

Hàm này không trực tiếp gửi mạng, ghi file, đọc đồng hồ hệ thống hay tạo số ngẫu nhiên. Nếu cần thời gian hoặc random, Server cung cấp dữ liệu đó qua đầu vào đã xác định.

## 2. Thiết lập game và Lobby

### 2.1. Số lượng Player

* Số người chơi được hỗ trợ: từ 8 đến 9.
* Cấu hình Demo chính thức: 9 Player.
* Cấu hình 8 Player: chưa được Sheet chốt; không được tự ý thay đổi số lượng Role để tạo cấu hình này.

### 2.2. Các trạng thái Lobby

Một Player trong Lobby cần có tối thiểu:

* `PlayerId`
* Tên hiển thị
* Trạng thái kết nối
* Trạng thái Ready

Host là người có quyền gửi yêu cầu bắt đầu game. Server vẫn phải kiểm tra điều kiện trước khi chấp nhận yêu cầu này.

### 2.3. Join

Khi nhận yêu cầu Join, Server kiểm tra:

1. Game còn ở `Lobby`.
2. Phòng chưa đạt giới hạn Player.
3. `PlayerId` không trùng với Player đang tồn tại trong phòng.
4. Dữ liệu đầu vào hợp lệ.

Nếu hợp lệ, Server thêm Player và phát `PlayerJoined`.

Nếu không hợp lệ, Server trả `GameError` phù hợp, không tạo Player trùng hoặc làm thay đổi GameState.

### 2.4. Leave và Disconnect

**[QUY ƯỚC PROJECT]**

* Trong Lobby, Player có thể Leave; Server loại Player khỏi phòng và phát `PlayerLeft`.
* Sau khi game bắt đầu, Disconnect không đồng nghĩa với việc Player chết.
* Nếu Player reconnect, Server khôi phục phiên của Player cũ thay vì tạo Player mới.
* Nếu Player không gửi hành động trước khi hết thời gian, Server xử lý theo quy tắc timeout đã cấu hình; mặc định đề xuất là `Pass` nếu hành động đó cho phép bỏ qua.
* Không được tự loại Player khỏi game chỉ vì mất kết nối, trừ khi nhóm bổ sung một luật riêng.

### 2.5. Ready

Player trong Lobby có thể bật hoặc tắt Ready.

Khi trạng thái Ready thay đổi, Server phát `ReadyChanged`.

Frontend không được tự kết luận rằng Player đã Ready nếu Server chưa xác nhận.

### 2.6. Điều kiện bắt đầu

Game chỉ được bắt đầu khi:

1. Số Player nằm trong khoảng 8–9.
2. Điều kiện Ready của phòng được đáp ứng.
3. Người gửi có quyền Start, thường là Host.
4. Game chưa bắt đầu.

Server phải kiểm tra lại toàn bộ điều kiện tại thời điểm xử lý `StartGame`.

### 2.7. Bắt đầu game

Khi `StartGame` hợp lệ, Server:

1. Tạo GameState ban đầu.
2. Phân Role theo cấu hình đã được nhóm thống nhất.
3. Xác định Team của từng Player.
4. Khởi tạo các trạng thái dùng một lần của Role.
5. Chuyển Phase từ `Lobby` sang `Night`.
6. Phát `GameStarted` và sự kiện cần thiết.
7. Gửi Role riêng cho từng Player.

Role không được gửi trong Public Event.

### 2.8. Quy tắc sau khi bắt đầu

Sau khi rời Lobby:

* Không cho Player mới tham gia ván đang chạy.
* Player không được tự đổi Role hoặc Team.
* Client không được trực tiếp sửa GameState.
* Mọi thay đổi phải đi qua Command được Server xác thực.

## 3. Phe và Role

### 3.1. Team

Game có hai phe chính:

* `Village`
* `Wolves`

Role quyết định Team của Player. Trong cấu hình hiện tại, Seer, Guard, Witch, Hunter và Villager thuộc Village; Werewolf thuộc Wolves.

### 3.2. Cấu hình Demo 9 người

| Role     | Team    | Số lượng |
| -------- | ------- | -------: |
| Werewolf | Wolves  |        3 |
| Seer     | Village |        1 |
| Guard    | Village |        1 |
| Witch    | Village |        1 |
| Hunter   | Village |        1 |
| Villager | Village |        2 |
| **Tổng** |         |    **9** |

Đây là cấu hình dùng cho Demo và kiểm thử chính.

### 3.3. Cấu hình 8 người

Sheet chưa chốt thành phần Role cho ván 8 người. Không được tự ý bỏ Werewolf, Villager hoặc Role đặc biệt.

Trước khi hỗ trợ chính thức 8 người, nhóm phải thống nhất một cấu hình cụ thể, kiểm tra điều kiện thắng và cập nhật bảng cấu hình cùng Test.

### 3.4. Bảo mật Role

* Player chỉ được biết Role của chính mình.
* Werewolf có thể nhận diện đồng đội theo luật của Project; nếu có thông tin này, Server gửi riêng cho những Player được phép nhận.
* Seer nhận kết quả kiểm tra riêng.
* Public Event không được chứa Role bí mật, kết quả Seer, hành động bí mật của Witch hoặc dữ liệu nội bộ có thể suy ra thông tin bí mật.
* Việc lộ Role khi chết được quy định riêng tại mục 10.

## 4. Các kiểu dữ liệu và trạng thái

### 4.1. Các kiểu dữ liệu Domain

Domain cần biểu diễn tối thiểu:

* `Role`
* `Team`
* `Phase`
* `Player`
* `GameState`
* `Command`
* `DomainEvent`
* `GameError`

Có thể bổ sung kiểu dữ liệu con để mô hình hóa Night Action, Vote, Death Cause và trạng thái dùng kỹ năng.

### 4.2. Role và Team

Ví dụ minh họa:

```haskell
data Role
  = Werewolf
  | Seer
  | Guard
  | Witch
  | Hunter
  | Villager
  deriving (Eq, Show)

data Team
  = Village
  | Wolves
  deriving (Eq, Show)
```

Hàm xác định Team nên là hàm thuần:

```haskell
teamOf :: Role -> Team
teamOf Werewolf = Wolves
teamOf _        = Village
```

### 4.3. Phase

Các Phase tối thiểu:

```haskell
data Phase
  = Lobby
  | Night
  | Day
  | Voting
  | GameOver
  deriving (Eq, Show)
```

Ý nghĩa:

* `Lobby`: tham gia phòng, Ready và Start.
* `Night`: các Role thực hiện hành động ban đêm.
* `Day`: công bố kết quả đêm và thảo luận.
* `Voting`: bỏ phiếu loại Player.
* `GameOver`: ván đấu đã kết thúc.

### 4.4. Player và GameState

`Player` cần biểu diễn tối thiểu:

* ID duy nhất.
* Tên hiển thị.
* Role.
* Trạng thái Alive/Dead.
* Trạng thái Ready khi ở Lobby.
* Trạng thái kết nối nếu Server cần quản lý reconnect.

`GameState` cần lưu đủ thông tin để xử lý luật mà không phụ thuộc vào Frontend, gồm:

* Danh sách Player.
* Phase hiện tại.
* Cấu hình game.
* Host hoặc quyền quản lý Lobby.
* Trạng thái hành động Night.
* Lượt Vote hiện tại.
* Trạng thái dùng kỹ năng một lần của Witch.
* Mục tiêu Guard ở đêm trước nếu áp dụng luật không bảo vệ cùng mục tiêu hai đêm liên tiếp.
* Kết quả và lịch sử cần thiết để resolve Death Effect.
* Kết quả thắng và thông tin kết thúc game.
* Sequence hoặc metadata phục vụ đồng bộ Client nếu cần.

Tên trường và cách chia Record do nhóm thống nhất trong Domain Types.

### 4.5. Witch cần biểu diễn hai Potion độc lập

**[BỔ SUNG – CÓ NGUỒN]**

Một số bộ luật cho phép Witch dùng Potion cứu và Poison trong cùng một đêm; một số biến thể giới hạn tối đa một Potion mỗi đêm. Vì Project cần một luật duy nhất, nhóm phải chọn rõ biến thể.

Để không giới hạn cấu trúc dữ liệu ngay từ đầu, không nên mô hình Witch bằng một lựa chọn đơn như:

```haskell
data NightChoice
  = WitchHeal PlayerId
  | WitchPoison PlayerId
```

nếu kiểu này khiến mỗi đêm chỉ biểu diễn được một trong hai hành động.

Một cách biểu diễn phù hợp hơn là hai trường độc lập:

```haskell
data WitchAction = WitchAction
  { healTarget   :: Maybe PlayerId
  , poisonTarget :: Maybe PlayerId
  } deriving (Eq, Show)
```

Validation phải kiểm tra Potion tương ứng đã dùng hay chưa, Target có hợp lệ hay không và luật của Project có cho phép dùng cả hai trong cùng một đêm hay không.

### 4.6. Invariant của GameState

Mọi trạng thái hợp lệ cần duy trì các invariant sau:

1. `PlayerId` không trùng.
2. Player đã chết không được thực hiện hành động yêu cầu Alive.
3. Command phải hợp lệ với Phase hiện tại.
4. Player không được Vote nhiều hơn số lần luật cho phép trong một lượt Vote.
5. Player không được tự sửa Role hoặc Team.
6. Thông tin bí mật không được phát công khai.
7. Khi Phase là `GameOver`, không chấp nhận Game Action làm thay đổi ván.
8. Các kỹ năng dùng một lần không được sử dụng vượt số lần quy định.
9. Một Player chỉ được chuyển từ Alive sang Dead một lần.
10. Mọi cập nhật trạng thái phải do Server xác nhận.

## 5. Vòng đời game

### 5.1. Luồng chính

```text
Lobby
  |
  | StartGame hợp lệ
  v
Night
  |
  | Resolve hành động đêm
  v
Day
  |
  | Discussion hoàn tất
  v
Voting
  |
  | Resolve kết quả Vote
  v
Check Win
  |
  +---- GameOver nếu có phe thắng
  |
  +---- Night nếu game tiếp tục
```

### 5.2. Chuyển Phase

Server chỉ chuyển Phase khi điều kiện tương ứng đã được đáp ứng.

* `Lobby -> Night`: StartGame hợp lệ.
* `Night -> Day`: các hành động đêm đã được thu thập hoặc hết thời gian, kết quả đã được resolve.
* `Day -> Voting`: giai đoạn thảo luận kết thúc.
* `Voting -> Night`: kết quả Vote và các hiệu ứng liên quan đã được xử lý, game chưa kết thúc.
* `Night/Day/Voting -> GameOver`: chỉ sau khi điều kiện thắng đã được xác định.

Không để Frontend tự chuyển Phase chỉ bằng cách thay đổi giao diện.

## 6. Command và Validation

### 6.1. Command tối thiểu

Các Command có thể gồm:

* `Join`
* `Leave`
* `SetReady`
* `StartGame`
* `SubmitNightAction`
* `SubmitVote`
* `SendChatMessage`
* `Reconnect`
* `RequestSnapshot`

Tên constructor thực tế có thể khác, nhưng ý nghĩa và quyền thực hiện phải nhất quán.

### 6.2. Quy trình Validation

Với mỗi Command, Server kiểm tra:

1. Player hoặc phiên gửi yêu cầu có tồn tại không.
2. Player có quyền thực hiện Command không.
3. Phase hiện tại có cho phép Command không.
4. Player còn sống nếu luật yêu cầu Alive không.
5. Target có tồn tại và hợp lệ không.
6. Role có quyền dùng kỹ năng đó không.
7. Kỹ năng đã dùng hết lượt chưa.
8. Player đã gửi hành động tương ứng chưa.
9. Command có phải yêu cầu trùng lặp không.
10. Nếu hợp lệ, trạng thái sau cập nhật có duy trì invariant không.

Nếu không hợp lệ, trả `Left GameError` và không cập nhật GameState.

### 6.3. Phân biệt lỗi luật và lỗi kết nối

Lỗi luật, chẳng hạn `WrongPhase`, khác với lỗi truyền tải hoặc mất kết nối.

Lỗi truyền tải không được tự động làm thay đổi Role, Alive/Dead hoặc kết quả game.

### 6.4. Idempotency

Đối với Command có thể bị gửi lại do timeout hoặc reconnect, Server nên hỗ trợ `requestId` hoặc cơ chế tương đương.

Nếu một request đã được xử lý, việc gửi lại cùng request không được thực hiện hiệu ứng lần thứ hai.

Ví dụ: một request Vote bị gửi lại không được tính thành hai phiếu.

## 7. Luật Night

### 7.1. Nguyên tắc

Night là giai đoạn các Role được phép thực hiện hành động bí mật.

* Chỉ Player còn sống mới được thực hiện Night Action, trừ khi có luật đặc biệt đã được nhóm thống nhất.
* Server thu thập và xác thực hành động.
* Client không được quyết định kết quả Night.
* Các hành động được resolve theo thứ tự cố định của Project.
* Hết thời gian mà Player chưa gửi hành động thì xử lý theo chính sách timeout đã thống nhất.

### 7.2. Werewolf

**[BỔ SUNG – CÓ NGUỒN]**

Các Werewolf còn sống cùng chọn một Player còn sống làm mục tiêu tấn công.

Để Server có kết quả xác định, Project dùng quy tắc đề xuất:

1. Mỗi Werewolf gửi lựa chọn bí mật.
2. Server tổng hợp lựa chọn hợp lệ.
3. Mục tiêu có số lựa chọn cao nhất là mục tiêu tấn công nếu có duy nhất một mục tiêu đứng đầu.
4. Nếu hòa ở vị trí cao nhất, đêm đó không có Werewolf Kill.

Quy tắc hòa là **quy ước của Project**, không phải luật bắt buộc của mọi bộ Ma Sói. Nếu nhóm chọn cơ chế biểu quyết lại, phải sửa tài liệu và Test tương ứng.

### 7.3. Seer

**[BỔ SUNG – CÓ NGUỒN]**

Mỗi Night, Seer còn sống được kiểm tra một Player hợp lệ.

Server trả kết quả riêng cho Seer, không Broadcast kết quả này cho những Player khác.

Để thống nhất cách triển khai, Project quy định kết quả cơ bản là:

* `Wolves` nếu Target có Team Wolves.
* `Village` nếu Target có Team Village.

Kết quả không tự động công khai và không buộc Seer phải tiết lộ trong Day.

### 7.4. Guard

**[BỔ SUNG – CÓ NGUỒN]**

Mỗi Night, Guard còn sống chọn một Player còn sống để bảo vệ.

Theo biến thể được tham khảo từ *The Werewolves of Miller’s Hollow: The Pact*:

* Guard được phép tự bảo vệ.
* Guard không được bảo vệ cùng một Player trong hai Night liên tiếp.
* Bảo vệ ngăn Werewolf Kill lên Target được bảo vệ.
* Bảo vệ không tự động ngăn Poison hoặc Hunter Shot.

Các giới hạn trên là luật được chọn cho Project nếu nhóm thống nhất sử dụng biến thể này. Không tự ý thêm quy tắc “Guard không được tự bảo vệ” vì đó không phải quy tắc của nguồn đang tham khảo.

### 7.5. Witch

**[BỔ SUNG – CÓ NGUỒN; CẦN CHỐT BIẾN THỂ]**

Witch có hai kỹ năng:

* `Heal`: cứu một mục tiêu khỏi Werewolf Kill.
* `Poison`: khiến một mục tiêu hợp lệ bị chết.

Mỗi Potion chỉ được sử dụng một lần trong toàn bộ game.

**Phương án được đề xuất để nhóm chốt:** dùng quy tắc của *The Werewolves of Miller’s Hollow: The Pact*:

1. Witch có thể cứu mục tiêu bị Werewolf tấn công.
2. Witch có thể tự cứu nếu bản thân là mục tiêu bị Werewolf tấn công.
3. Witch có thể dùng Heal và Poison trong cùng một Night nếu cả hai Potion còn.
4. Witch không thể dùng lại Potion đã hết.
5. Heal chỉ hủy Werewolf Kill; không tự động hủy Poison hoặc Hunter Shot.
6. Nếu Target không hợp lệ hoặc Witch không còn Potion tương ứng, Server từ chối hành động.

Lưu ý: không phải mọi phiên bản Ma Sói đều cho dùng hai Potion trong cùng một Night. Nếu nhóm muốn biến thể chỉ dùng tối đa một Potion mỗi Night, phải ghi rõ đó là quy ước của Project và cập nhật Validation, Domain và Test.

### 7.6. Hunter

**[BỔ SUNG – CÓ NGUỒN; CẦN CHỐT BIẾN THỂ]**

Theo biến thể được tham khảo từ *The Werewolves of Miller’s Hollow: The Pact*, Hunter có thể bắn một Player khi chết do Werewolf Kill hoặc bị Village loại qua Vote.

* Target phải hợp lệ theo luật của Project.
* Hunter Shot là một Death Effect riêng.
* Nếu Hunter Shot làm một Player khác chết và Player đó có Death Effect hợp lệ, Server tiếp tục xử lý chuỗi hiệu ứng theo luật.
* Hunter không được kích hoạt kỹ năng nhiều lần cho cùng một lần chết.

Nguồn tham khảo không nên được hiểu là mọi phiên bản Ma Sói đều có cùng điều kiện kích hoạt Hunter. Nhóm cần giữ nguyên biến thể đã chọn khi implement.

### 7.7. Thứ tự Resolve Night

**[QUY ƯỚC PROJECT]**

Để kết quả có tính xác định, Project đề xuất thứ tự:

```text
1. Thu thập và Validate Night Action
2. Seer kiểm tra
3. Guard chọn mục tiêu bảo vệ
4. Werewolf xác định mục tiêu tấn công
5. Witch thực hiện Heal/Poison
6. Resolve các nguyên nhân chết ban đêm
7. Resolve Hunter nếu điều kiện kích hoạt được đáp ứng
8. Resolve các Death Effect dây chuyền
9. Check Win
10. Nếu chưa kết thúc, chuyển sang Day
```

Thứ tự này là quy ước kỹ thuật của Project, không phải thứ tự bắt buộc của mọi phiên bản Ma Sói.

Server cần định nghĩa rõ cách phối hợp Guard và Witch. Theo phương án đề xuất, Heal có thể cứu mục tiêu bị Werewolf tấn công kể cả khi Guard không bảo vệ mục tiêu đó; nếu mục tiêu đã được Guard bảo vệ thì Werewolf Kill vốn đã bị ngăn.

### 7.8. Nhiều hiệu ứng tác động cùng một Player

Nếu một Player đồng thời là mục tiêu của nhiều Death Effect:

* Server phải resolve theo quy tắc đã chốt.
* Một Player chỉ chuyển từ Alive sang Dead một lần.
* Không phát nhiều sự kiện loại bỏ cho cùng một lần chết.
* Nếu Player đã chết trước khi một hiệu ứng khác được resolve, hiệu ứng sau phải theo quy tắc Target đã chết của Project.
* Check Win chỉ diễn ra sau khi chuỗi Death Effect hoàn tất.

## 8. Luật Day và Chat

### 8.1. Bắt đầu Day

Khi Night đã được resolve, Server chuyển sang `Day`.

Server công bố thông tin được phép công khai, ví dụ danh sách người chết trong đêm. Các thông tin Role hoặc hành động bí mật chỉ được công khai theo luật đã chọn.

### 8.2. Thảo luận

Player còn sống được thảo luận và đưa ra nghi vấn.

Player đã chết:

* Không được gửi Vote.
* Không được thực hiện Night Action.
* Không được tiếp tục tham gia các hoạt động mà luật chỉ dành cho Player còn sống.

**[QUY ƯỚC PROJECT]** Để tránh ảnh hưởng đến ván đấu, Player đã chết không được gửi Chat công khai vào kênh thảo luận của Player còn sống. Nếu muốn hỗ trợ kênh người xem riêng, kênh đó phải được tách khỏi kênh game chính.

### 8.3. Chat

Chat Message phải được Server xác thực và gắn với Player gửi.

Server không được tin dữ liệu Role hoặc trạng thái Alive/Dead do Frontend tự gửi.

Chat không được phép làm thay đổi GameState hoặc được xem như Command luật chơi, trừ khi Project định nghĩa riêng.

### 8.4. Kết thúc Day

Day kết thúc khi hết thời gian hoặc khi điều kiện chuyển sang Voting được đáp ứng.

Thời gian Day nên được quản lý bởi Server. Clock được inject để Test có thể sử dụng thời gian giả thay vì phụ thuộc thời gian thực.

## 9. Luật Voting

### 9.1. Điều kiện Vote

**[BỔ SUNG – CÓ NGUỒN]**

* Chỉ Player còn sống được Vote.
* Vote chỉ hợp lệ trong `Voting`.
* Target phải là Player tồn tại và còn sống.
* Player không được tự Vote nếu Project không cho phép.
* Một Player chỉ được Vote theo giới hạn của lượt hiện tại.
* Server là thành phần xác nhận phiếu hợp lệ.

### 9.2. Tính kết quả Vote

Server tổng hợp các phiếu hợp lệ theo Player ID.

Không dùng kết quả tính riêng trên Frontend làm kết quả chính thức.

### 9.3. Hòa phiếu

Vì các phiên bản Ma Sói xử lý hòa phiếu khác nhau, Project cần một quy tắc duy nhất.

**[QUY ƯỚC PROJECT – ĐỀ XUẤT]**

1. Nếu một Player có số phiếu cao nhất duy nhất, Player đó bị loại.
2. Nếu hòa ở số phiếu cao nhất, tổ chức một lượt Vote lại chỉ giữa các Player hòa.
3. Nếu lượt Vote lại vẫn hòa, không ai bị loại trong ngày đó.
4. Nếu không có phiếu hợp lệ, không ai bị loại.

Nếu nhóm chọn cơ chế khác, cập nhật quy tắc này và các Test liên quan trước khi code.

### 9.4. Sau khi Vote

Sau khi xác định người bị loại:

1. Server cập nhật trạng thái Alive/Dead.
2. Phát sự kiện loại Player.
3. Resolve Hunter hoặc Death Effect liên quan nếu điều kiện được đáp ứng.
4. Kiểm tra điều kiện thắng.
5. Nếu game chưa kết thúc, chuyển sang Night.

## 10. Chết, loại khỏi game và công khai Role

### 10.1. Trạng thái chết

Khi Player chết, Server cập nhật trạng thái từ Alive sang Dead.

Player đã chết không được thực hiện hành động chỉ dành cho Player còn sống.

### 10.2. Death Cause

Nên biểu diễn nguyên nhân chết để xử lý đúng luật:

* Werewolf Kill
* Witch Poison
* Village Vote
* Hunter Shot
* Nguyên nhân khác nếu nhóm bổ sung Role

Nguyên nhân chết không nên chỉ được suy luận từ một thông báo giao diện.

### 10.3. Công khai Role khi chết

Các bộ luật Ma Sói có cách công khai Role khác nhau: có bộ yêu cầu lật Role khi chết, có bộ giữ Role bí mật.

**[QUY ƯỚC PROJECT – ĐỀ XUẤT]** Với Demo, khi Player bị loại, Server công khai Role của Player đó. Đây là lựa chọn của Project, không phải quy tắc bắt buộc của tất cả phiên bản.

Nếu nhóm muốn giữ Role bí mật khi chết, phải cập nhật `PlayerEliminated`, Public Event và Test về bảo mật.

### 10.4. Death Effect dây chuyền

Nếu một Death Effect gây ra cái chết khác, Server phải tiếp tục xử lý hiệu ứng hợp lệ cho đến khi không còn hiệu ứng cần giải quyết.

Server không được Check Win giữa chừng rồi bỏ qua một hiệu ứng bắt buộc còn lại.

## 11. Điều kiện thắng

### 11.1. Village thắng

**[BỔ SUNG – CÓ NGUỒN]**

Village thắng khi không còn Werewolf sống:

```text
wolvesAlive == 0
```

### 11.2. Wolves thắng

Wolves thắng khi số Werewolf sống bằng hoặc lớn hơn tổng số Player Village sống:

```text
wolvesAlive >= villageAlive
```

Trong đó `villageAlive` bao gồm mọi Player thuộc Team Village, kể cả Seer, Guard, Witch, Hunter và Villager.

Các điều kiện này phù hợp với cách tính thắng phổ biến được nêu trong những bộ luật Ma Sói tham khảo, nhưng Project vẫn phải cố định công thức trên làm quy tắc chính thức.

### 11.3. Thời điểm Check Win

Chỉ Check Win sau khi toàn bộ Death Effect của Night hoặc Vote đã được resolve, bao gồm Hunter nếu có.

Khi một phe thắng:

1. Chuyển Phase sang `GameOver`.
2. Lưu kết quả thắng.
3. Phát `GameEnded`.
4. Từ chối Game Action tiếp theo.

### 11.4. Trường hợp đặc biệt

Nếu trạng thái đặc biệt khiến cả hai điều kiện thắng cùng thỏa mãn hoặc không còn Player sống, Project phải có quy tắc rõ ràng.

**[QUY ƯỚC PROJECT – ĐỀ XUẤT]**

* Ưu tiên xử lý toàn bộ Death Effect trước.
* Nếu sau khi resolve chỉ còn một phe đáp ứng điều kiện thắng, phe đó thắng.
* Nếu không còn Player sống và không có phe nào được xác định thắng theo công thức, kết quả là Draw.
* Không tự suy diễn Draw nếu tình huống đã được điều kiện thắng của một phe xác định.

## 12. GameError

Domain cần có các lỗi phù hợp với những tình huống không hợp lệ.

| GameError              | Ý nghĩa                                          |
| ---------------------- | ------------------------------------------------ |
| `WrongPhase`           | Command không hợp lệ với Phase hiện tại          |
| `DeadPlayer`           | Player đã chết nhưng gửi hành động yêu cầu Alive |
| `InvalidTarget`        | Target không tồn tại hoặc không hợp lệ           |
| `AlreadyVoted`         | Player đã Vote trong lượt hiện tại               |
| `PlayerNotFound`       | Không tìm thấy Player                            |
| `PlayerAlreadyExists`  | Player ID đã tồn tại                             |
| `GameNotStarted`       | Game Action được gửi khi game chưa bắt đầu       |
| `GameAlreadyStarted`   | Yêu cầu Start khi game đã bắt đầu                |
| `GameAlreadyOver`      | Game Action được gửi sau GameOver                |
| `NotAuthorized`        | Player không có quyền thực hiện Command          |
| `RoleCannotAct`        | Role không có quyền thực hiện hành động đó       |
| `AbilityAlreadyUsed`   | Kỹ năng dùng một lần đã hết                      |
| `NotReady`             | Điều kiện Ready chưa đáp ứng                     |
| `RoomFull`             | Phòng đã đạt giới hạn Player                     |
| `DuplicateRequest`     | Request trùng đã được xử lý                      |
| `InvalidConfiguration` | Cấu hình Role hoặc số lượng Player không hợp lệ  |

Tên lỗi thực tế có thể được điều chỉnh theo Domain Types, nhưng không được tạo các lỗi trùng ý nghĩa mà không có lý do.

## 13. Edge Cases

Các tình huống sau cần có quy tắc và Test.

| Tình huống                                       | Cách xử lý đề xuất                                        |
| ------------------------------------------------ | --------------------------------------------------------- |
| Player Join với ID trùng                         | Từ chối                                                   |
| Player Join khi game đã bắt đầu                  | Từ chối                                                   |
| Player Start khi không phải Host                 | `NotAuthorized`                                           |
| Start khi chưa đủ điều kiện                      | Từ chối                                                   |
| Player gửi Night Action trong Day                | `WrongPhase`                                              |
| Player chết gửi Vote                             | `DeadPlayer`                                              |
| Target không tồn tại                             | `InvalidTarget`                                           |
| Witch dùng Potion đã hết                         | `AbilityAlreadyUsed`                                      |
| Witch gửi cả Heal và Poison                      | Validate riêng từng Potion theo luật đã chốt              |
| Guard bảo vệ cùng Target hai Night liên tiếp     | Từ chối theo biến thể đã chọn                             |
| Vote hòa                                         | Thực hiện quy tắc hòa đã chốt                             |
| Hunter kích hoạt nhiều lần cho cùng một lần chết | Chỉ xử lý một lần                                         |
| Game đã GameOver nhưng nhận Command              | Từ chối                                                   |
| Client gửi lại Request                           | Không lặp lại hiệu ứng                                    |
| Player reconnect                                 | Khôi phục Player cũ, không tạo Player mới                 |
| Player mất kết nối giữa Night                    | Xử lý theo chính sách timeout, không tự ý sửa Role        |
| Nhiều Death Effect cùng tác động một Player      | Player chỉ chết một lần                                   |
| Game kết thúc trong chuỗi Death Effect           | Resolve hết hiệu ứng hợp lệ trước khi Check Win cuối cùng |
| Public Event có thông tin riêng                  | Redact trước khi gửi                                      |
| Hai Command cạnh tranh cập nhật cùng trạng thái  | Server tuần tự hóa hoặc đồng bộ để bảo đảm invariant      |

### 13.1. Guard và Witch cùng tác động một mục tiêu

Theo phương án được đề xuất:

* Nếu Guard bảo vệ Target bị Werewolf chọn, Werewolf Kill bị ngăn.
* Nếu Target không được Guard bảo vệ nhưng Witch cứu hợp lệ, Werewolf Kill bị ngăn bởi Heal.
* Guard không ngăn Poison hoặc Hunter Shot.
* Witch Heal không hồi sinh một Player đã chết; Heal chỉ ngăn một cái chết còn đang được resolve theo luật.

### 13.2. Player chết vì Poison

Theo biến thể Hunter được tham khảo, không mặc định kích hoạt Hunter Shot chỉ vì Hunter chết do Poison. Điều kiện kích hoạt phải dựa trên Death Cause và luật đã chốt, không dựa đơn thuần vào việc Player chuyển sang Dead.

### 13.3. Không có hành động đúng hạn

Nếu Night Action hoặc Vote hết thời gian:

* Server xác định kết quả theo chính sách timeout đã cấu hình.
* Không được để Client tự chọn kết quả thay cho Player.
* Quy tắc timeout phải nhất quán giữa Server và Test.

## 14. DomainEvent

### 14.1. Event tối thiểu

DomainEvent cần mô tả những thay đổi có ý nghĩa đối với Client hoặc các thành phần Server.

Danh sách tối thiểu đề xuất:

* `PlayerJoined`
* `PlayerLeft`
* `ReadyChanged`
* `GameStarted`
* `PhaseChanged`
* `PrivateRoleAssigned`
* `PrivateResult`
* `VoteUpdated`
* `PlayerEliminated`
* `NightResolved`
* `ChatMessage`
* `GameEnded`

Có thể bổ sung `NightActionSubmitted`, `ReconnectAccepted` hoặc `SnapshotCreated` nếu cần.

### 14.2. Public Event và Private Event

Event cần được phân loại theo đối tượng nhận.

**Public Event:** chỉ chứa thông tin mọi Player được phép biết.

**Private Event:** chỉ gửi cho Player có quyền nhận, ví dụ:

* Role được phân cho chính Player.
* Kết quả Seer.
* Thông tin bí mật được luật cho phép.

Không gửi Private Event bằng cách Broadcast rồi yêu cầu Frontend tự ẩn dữ liệu.

### 14.3. Redaction và log

* Public Event phải được tạo từ dữ liệu đã được kiểm tra quyền công khai.
* Log không được ghi Role bí mật, kết quả Seer hoặc dữ liệu riêng không cần thiết.
* Không tái sử dụng trực tiếp một cấu trúc nội bộ chứa dữ liệu bí mật làm JSON public.
* Nếu dùng một Event nội bộ cho nhiều người nhận, phải tạo phiên bản đã lọc dữ liệu theo quyền của từng người nhận.

## 15. Quy tắc Protocol và đồng bộ

### 15.1. Protocol

Protocol chuyển dữ liệu giữa Frontend và Server. Protocol không tự quyết định luật chơi.

Mỗi Message cần có đủ thông tin để Server xác định:

* Loại Message.
* Player hoặc phiên gửi.
* Payload.
* Request ID hoặc cơ chế nhận diện request trùng nếu cần.

Server phải xác thực dữ liệu nhận được trước khi chuyển thành Command Domain.

### 15.2. Snapshot và reconnect

**[YÊU CẦU ĐỘ TIN CẬY]**

Khi reconnect, Client có thể gửi `lastSequence` hoặc thông tin tương đương.

Server trả Snapshot hoặc những Event còn thiếu để Client đồng bộ.

* Không tạo Player mới chỉ vì Client reconnect.
* Không phát lại hiệu ứng game đã thực hiện.
* Không để Client nhận thông tin riêng của Player khác trong Snapshot.
* Nếu không thể replay an toàn, Server trả Snapshot hiện tại đã được lọc theo quyền.

### 15.3. Backpressure và lỗi kết nối

Server cần xử lý trường hợp Client nhận dữ liệu chậm hoặc mất kết nối.

* Không để hàng đợi không giới hạn tăng vô tận.
* Có chính sách xử lý lỗi gửi Message.
* Không xem việc gửi Message thất bại là bằng chứng rằng Command chưa được xử lý.
* Request ID hoặc Sequence giúp Client đồng bộ mà không lặp lại hiệu ứng.

## 16. Server và tính đồng thời

### 16.1. Server authoritative

Server giữ GameState chính thức và xác thực tất cả Command.

Frontend chỉ gửi yêu cầu; không được gửi một GameState hoàn chỉnh để Server chấp nhận nguyên trạng.

### 16.2. STM

Có thể sử dụng:

* `TVar GameState` để giữ trạng thái game.
* `TQueue` hoặc `TChan` để xử lý Message/Event tùy thiết kế.
* STM để đồng bộ việc cập nhật trạng thái.

Mục tiêu là tránh hai Command cạnh tranh làm hỏng invariant hoặc khiến một hành động được xử lý hai lần.

### 16.3. Pure Core và hiệu ứng bên ngoài

Logic xác thực và cập nhật trạng thái nên nằm trong các hàm thuần.

Server phụ trách:

* Nhận Message.
* Xác thực phiên.
* Lấy trạng thái hiện tại.
* Gọi hàm xử lý Domain.
* Commit trạng thái mới theo cơ chế đồng bộ.
* Gửi Event cho đúng người nhận.

### 16.4. Clock và Random

* Random dùng để phân Role cần được kiểm soát bởi Server.
* Clock được inject vào thành phần cần thời gian.
* Test sử dụng clock giả và seed cố định khi cần tái lập kết quả.
* Không để Test phụ thuộc vào thời gian hệ thống hoặc random không kiểm soát.

## 17. Mapping luật sang Code và Test

### 17.1. Domain Types và Validation

Cần kiểm thử:

* Role và Team.
* Phase.
* Player và GameState.
* Quyền thực hiện Command.
* Target hợp lệ.
* Trạng thái Alive/Dead.
* Giới hạn kỹ năng.
* Invariant của GameState.

### 17.2. Night Rules

Cần kiểm thử:

* Werewolf chọn mục tiêu.
* Trường hợp hòa lựa chọn Werewolf.
* Seer nhận kết quả riêng.
* Guard bảo vệ hợp lệ.
* Guard không bảo vệ cùng mục tiêu hai Night liên tiếp nếu dùng luật này.
* Witch Heal.
* Witch Poison.
* Witch sử dụng cả hai Potion theo biến thể đã chốt.
* Hunter kích hoạt đúng điều kiện.
* Nhiều Death Effect.
* Check Win sau khi resolve đầy đủ.

### 17.3. Voting và Win Rules

Cần kiểm thử:

* Vote hợp lệ.
* Vote sai Phase.
* Vote của Player đã chết.
* Vote trùng.
* Hòa phiếu.
* Không có phiếu hợp lệ.
* Village thắng khi không còn Werewolf.
* Wolves thắng khi đạt parity theo công thức đã chốt.
* GameOver từ chối hành động tiếp theo.

### 17.4. Test theo Sheet

Mức kiểm thử tối thiểu:

* 14 Unit Tests.
* 3 Property Tests, mỗi Property chạy 100 mẫu.
* 2 Integration Tests.

Đây là mức tối thiểu; nhóm có thể viết nhiều hơn khi có thêm luật và Edge Case.

### 17.5. Property Test đề xuất

Ví dụ các thuộc tính có thể kiểm tra:

1. Mọi `PlayerId` trong GameState hợp lệ đều duy nhất.
2. Command không hợp lệ trả `Left GameError` và không tạo GameState mới.
3. Player đã chết không thể thực hiện Command chỉ dành cho Player còn sống.

Với Property Test, cần tạo dữ liệu đầu vào hợp lệ và bất hợp lệ phù hợp để kiểm tra thuộc tính, không chỉ chạy lại một ví dụ cố định.

### 17.6. Integration Test

Hai Integration Test tối thiểu có thể bao gồm:

1. Luồng Lobby → Start → Night → Day → Voting → Night.
2. Luồng kết thúc game: hành động gây chết → Resolve Death Effect → Check Win → GameOver, đồng thời kiểm tra Event public/private.

## 18. Happy Path và Error Path

### 18.1. Happy Path

Luồng cơ bản:

```text
Join
  -> Ready
  -> StartGame
  -> Role Assignment
  -> Night Actions
  -> Resolve Night
  -> Day
  -> Voting
  -> Resolve Vote
  -> Check Win
  -> Night hoặc GameOver
```

Ở mỗi bước, Server kiểm tra điều kiện trước khi cập nhật trạng thái.

### 18.2. Error Path

Ví dụ:

```text
Player chết
  -> Gửi Vote
  -> Validation
  -> Left DeadPlayer
  -> Không cập nhật GameState
```

Một ví dụ khác:

```text
Phase = Day
  -> Nhận Night Action
  -> Validation
  -> Left WrongPhase
  -> Không cập nhật GameState
```

Error Path phải trả lỗi phù hợp, không làm hỏng trạng thái và không tạo Event thành công giả.

## 19. Cấu trúc Repository và triển khai

### 19.1. Cấu trúc thư mục

Cấu trúc tối thiểu:

```text
werewolf-haskell/
├── src/
│   ├── Domain/
│   ├── Protocol/
│   └── Server/
├── app/
├── web/
├── test/
├── docs/
│   └── game-rules.md
├── cabal.project
├── *.cabal
├── compose.yaml
└── .github/
    └── workflows/
```

Tên file và module cụ thể có thể thay đổi, nhưng ranh giới giữa Domain, Protocol, Server và Frontend cần được giữ rõ.

### 19.2. Build và CI

* GHC/Cabal cần được thống nhất trong nhóm.
* Build thành công trên môi trường các thành viên đã thống nhất.
* CI chạy Build và Test.
* Docker phải có thể Build/Run theo cấu hình của Repository.
* Server phục vụ Frontend trong `web/` theo phương án triển khai của Project.
* Port Demo theo Sheet: `8080`.
* Không để CI chỉ kiểm tra cú pháp mà bỏ qua Test luật cốt lõi.

## 20. Nguồn tham khảo và cách chốt luật

### 20.1. Nguồn luật

Các nguồn dưới đây được dùng để bổ sung những điểm mà Sheet chưa quy định rõ. Vì Ma Sói có nhiều biến thể, nguồn tham khảo không tự động trở thành luật của Project.

**[S1] Ultimate Werewolf – Official Rules**

https://board-game-rules.com/wp-content/uploads/2025/01/ultimate-werewolf-ultimate-edition_Official-Rules.pdf

Tham khảo cách vận hành Night/Day, Werewolf chọn mục tiêu, Seer kiểm tra, công bố người chết và điều kiện kết thúc. Một số quy tắc cụ thể trong tài liệu này có thể khác biến thể Project.

**[S2] The Werewolves of Miller’s Hollow: The Pact – Rulebook**

https://cdn.svc.asmodee.net/production-asmodeeca/uploads/2023/07/WerewolvesThePact_EN_Rules.pdf

Tham khảo các Role và hành động đặc biệt, nhất là Defender/Guard, Witch và Hunter. Đây là một biến thể cụ thể, không đại diện cho mọi phiên bản Ma Sói.

**[S3] Stellar Factory – Werewolf: How to Play**

https://playwerewolf.co/pages/rules

Tham khảo luồng Night/Day, thảo luận, Vote và điều kiện thắng cơ bản.

**[S4] Stellar Factory – Character Roles**

https://playwerewolf.co/pages/character-roles

Tham khảo mô tả Role và các lựa chọn biến thể, bao gồm Seer, Witch và cách vận hành các kỹ năng.

### 20.2. Phân biệt luật nguồn và luật Project

Khi trích một nguồn, cần phân biệt:

* Luật xuất hiện trong nguồn.
* Luật được nhóm lựa chọn để áp dụng.
* Luật kỹ thuật cần có để Server hoạt động đúng.
* Luật còn cần nhóm xác nhận.

Ví dụ:

* Guard tự bảo vệ và không bảo vệ cùng một người hai đêm liên tiếp là quy tắc trong biến thể *The Pact*.
* Witch có thể sử dụng cả Heal và Poison trong cùng một đêm phụ thuộc bộ luật được chọn.
* Thứ tự resolve cố định, cách xử lý request trùng và redaction Event là quyết định thiết kế của Project.
* Cấu hình Demo 9 người là yêu cầu của Sheet, không phải suy ra từ một bộ luật thương mại.

### 20.3. Quy trình thay đổi luật

Mọi thay đổi phải theo thứ tự:

```text
Đề xuất thay đổi
  ↓
Đối chiếu Sheet và nguồn
  ↓
Đánh dấu phần cần nhóm xác nhận
  ↓
Nhóm thống nhất
  ↓
Cập nhật docs/game-rules.md
  ↓
Cập nhật Domain/Validation
  ↓
Cập nhật Protocol/Server/Frontend nếu cần
  ↓
Cập nhật Test
  ↓
Build + Test
  ↓
Review và Merge
```

Không được tự ý implement một luật chưa được thống nhất rồi để các module sử dụng các cách hiểu khác nhau.

### 20.4. Nguyên tắc cuối cùng

`docs/game-rules.md` là nguồn thống nhất về luật chơi của Project.

Nếu code, Protocol, Frontend hoặc Test mâu thuẫn với tài liệu, nhóm phải xác định và sửa phần sai sau khi đã chốt quy tắc. Không dùng việc “mã đang chạy như vậy” làm lý do để tự động coi đó là luật chính thức.
