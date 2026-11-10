# StudyWith

Apple Music と連動するポモドーロタイマーのサンプル iOS アプリです。
作業中は Apple Music のプレイリストを流し、作業時間が終わったら一時停止し、休憩が明けたら続きから再開します。

- iOS 26 以降（iPhone）／Swift 6／SwiftUI
- 状態管理：Observation（`@Observable`）
- 非同期処理：Swift Concurrency
- 音楽：MusicKit（`ApplicationMusicPlayer`）
- 通知：UserNotifications
- 外部ライブラリなし

現在は**フェーズ1**（タイマー、Apple Music 連動、バックグラウンド対策）まで実装済みです。
フェーズ2（AlarmKit 連携）は Issue で管理しています。

---

## 1. ファイル構成

```
studywith/
├── studywith-Info.plist             … Info.plist の追加キー（利用目的の説明文）
├── studywith/
│   ├── StudywithApp.swift           … エントリポイント。コントローラーの生成、起動時の許可リクエスト、scenePhase の監視
│   ├── PomodoroController.swift     … 画面とロジックの仲介役（@Observable）。音楽・通知・画面スリープの副作用をまとめて反映
│   ├── Timer/                       … ★ UI に依存しない純粋なロジック（ユニットテスト対象）
│   │   ├── TimerState.swift         … 5つの状態（待機中・作業中・短い休憩・長い休憩・一時停止中）の enum と Phase
│   │   ├── PomodoroEngine.swift     … 状態遷移と残り時間の計算。現在時刻は引数で受け取る
│   │   └── PomodoroSettings.swift   … 設定値（各時間・サイクル数）と UserDefaults への保存
│   ├── Services/
│   │   ├── MusicService.swift       … MusicKit：許可、加入状況、プレイリスト取得、再生・一時停止
│   │   └── NotificationService.swift… ローカル通知の予約・取り消し
│   └── Views/
│       ├── MainView.swift           … メイン画面（残り時間、フェーズ、サイクル、操作ボタン）
│       ├── MusicStatusView.swift    … Apple Music が使えない理由の案内、加入オファー
│       ├── NowPlayingView.swift     … 再生中の曲名とアートワーク
│       ├── PlaylistPickerView.swift … プレイリスト選択（ライブラリ／カタログ検索のタブ）
│       └── SettingsView.swift       … 設定画面
└── studywithTests/
    └── PomodoroEngineTests.swift    … タイマーロジックのユニットテスト（Swift Testing）
```

### 設計のポイント

| ポイント | 内容 |
| --- | --- |
| 状態は enum | `TimerState` の5ケースで表す。動作中の状態は「終了時刻 (`endDate`)」を持つ |
| 残り時間は時刻から計算 | `endDate - 現在時刻`。`Timer` の回数は数えないので、バックグラウンドから戻っても正しい |
| ロジックを UI から分離 | `PomodoroEngine` は値型で、`now: Date` を引数で受け取る。テストで「40分後」なども即座に再現できる |
| 復帰時の追いつき | `advanceIfNeeded(at:)` は、過ぎたフェーズをループで進める。次のフェーズは「前のフェーズの終了時刻」から始まる |
| 副作用のルールは1つ | 「作業フェーズが動いている間だけ音楽を流し、画面スリープを止める」。状態が変わるたびに通知を予約し直す |

### 状態遷移

```
待機中 ──開始──▶ 作業中 ──時間切れ/スキップ──▶ 短い休憩 or 長い休憩（N回ごと）
                  ▲                                      │
                  └──────────時間切れ/スキップ───────────┘

作業中・休憩中 ──一時停止──▶ 一時停止中 ──再開──▶ 元のフェーズ
どの状態でも ──リセット──▶ 待機中
```

---

## 2. Xcode でのセットアップ手順

### 2-1. Apple Developer Portal で MusicKit を有効にする

MusicKit は Xcode の Capability ではなく、App ID の **App Services** で有効にします。
有料の Apple Developer Program のアカウントが必要です。

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) を開く
2. **Identifiers** で、このアプリの App ID（Bundle ID：`KaitoMuraoka.studywith`）を選ぶ
   - まだない場合は「+」→「App IDs」→「App」で、Bundle ID を Explicit で登録する
   - Xcode の Automatic Signing で一度ビルドしていれば自動で作られています
3. **App Services** タブを開き、**MusicKit** にチェックを入れて **Save**
4. 反映まで数分かかることがあります。反映前に起動すると、カタログ検索や再生でエラーになります

> MusicKit の開発者トークンは、この設定をしておけば OS が自動で発行します。アプリ側でトークンを扱う必要はありません。

### 2-2. Info.plist

プロジェクト直下の `studywith-Info.plist` に、次の2つのキーを入れてあります。
ビルド設定 `INFOPLIST_FILE = studywith-Info.plist` と `GENERATE_INFOPLIST_FILE = YES` により、自動生成される Info.plist に合成されます。

| キー | 用途 |
| --- | --- |
| `NSAppleMusicUsageDescription` | Apple Music へのアクセス許可ダイアログの説明文（フェーズ1で使用） |
| `NSAlarmKitUsageDescription` | AlarmKit の許可ダイアログの説明文（フェーズ2で使用。先に入れておいても害はない） |

> `studywith-Info.plist` は、同期フォルダ（`studywith/`）の外に置いています。
> フォルダの中に置くと、リソースとしてもコピーされて「Multiple commands produce Info.plist」エラーになるためです。

### 2-3. Capability

フェーズ1で Xcode の **Signing & Capabilities** に追加が必要なものは**ありません**。

| 項目 | 必要か | 理由 |
| --- | --- | --- |
| MusicKit | Portal の App Services のみ | Xcode の Capability 一覧にはない |
| Push Notifications | 不要 | ローカル通知はリモート通知の Capability なしで使える |
| Background Modes | 原則不要 | 無音再生などでアプリを生かす手法は使わない。ただし下の「要実機検証」参照 |
| AlarmKit | 不要 | Info.plist の `NSAlarmKitUsageDescription` だけでよい（フェーズ2） |

> **要実機検証**：`ApplicationMusicPlayer` の再生が、画面ロックやバックグラウンド中も続くか。
> 止まってしまう場合は Background Modes の「Audio, AirPlay, and Picture in Picture」を有効にしてください。
> 実際に音楽を流す用途なので、審査上の問題はありません（禁止しているのは「無音を流し続けてアプリを生かす」手法です）。

### 2-4. ビルド設定（変更済み）

| 設定 | 値 |
| --- | --- |
| iOS Deployment Target | 26.0 |
| Swift Language Version | Swift 6 |
| Targeted Device Family | iPhone |
| Default Actor Isolation | MainActor（テンプレートのまま） |

### 2-5. 実機で動かす

1. `studywith.xcodeproj` を Xcode で開く
2. ターゲット `studywith` の **Signing & Capabilities** で Team を選ぶ（Bundle ID は 2-1 で MusicKit を有効にしたものと同じにする）
3. iPhone を接続し、実行先に選んで ⌘R
4. ユニットテストは ⌘U（シミュレータでも可）

---

## 3. 実機での動作確認チェックリスト

MusicKit の再生はシミュレータでは確認できないため、実機（Apple Music に加入済みの Apple Account）で確認します。
タイマーの確認は、設定画面で各時間を **1分** にすると早く終わります。

### 許可と加入状況
- [ ] 初回起動で「通知」と「Apple Music」の許可ダイアログが出る
- [ ] Apple Music の許可を拒否すると、メイン画面に案内と「設定を開く」ボタンが出る。ボタンで設定アプリが開く
- [ ] 設定アプリで許可した後、アプリを開き直すと案内が消える
- [ ] Apple Music 未加入の Apple Account では「加入していないため音楽機能は使えません」と出る
- [ ] 未加入で、トライアル対象のアカウントでは「Apple Music を試す」で加入シートが表示される
- [ ] 加入状況が変わると（シートから加入など）、案内が自動で消える

### プレイリスト選択
- [ ] 「ライブラリ」タブに自分のプレイリストが表示される
- [ ] 「カタログ検索」で「集中」「Lo-fi」のボタンや検索欄から検索できる
- [ ] プレイリストを選ぶと画面が閉じ、メイン画面に「〇〇を作業中に再生します」と出る

### タイマーと音楽の連動
- [ ] 「開始」で作業中になり、選んだプレイリストの再生が始まる。曲名とアートワークが表示される
- [ ] ミュージックアプリの再生キューが変わっていない（`ApplicationMusicPlayer` を使っているため）
- [ ] 「一時停止」でタイマーと音楽が止まり、「再開」で両方とも続きから再開する
- [ ] 作業時間が終わると短い休憩になり、音楽が一時停止する
- [ ] 休憩が終わると作業に戻り、音楽が**続きから**再開する（最初の曲に戻らない）
- [ ] 設定した回数ごとに長い休憩になる。「サイクル n / N」の表示が正しく進む
- [ ] 作業中に「スキップ」すると休憩になり音楽が止まる。休憩中の「スキップ」で作業になり音楽が再開する
- [ ] 「リセット」で待機中に戻り、音楽が止まる
- [ ] 作業中に別のプレイリストを選ぶと、すぐに新しいプレイリストに切り替わる

### 画面スリープ
- [ ] 作業中は、自動ロックの時間を過ぎても画面が消えない
- [ ] 休憩中・待機中・一時停止中は、自動ロックの時間で画面が消える

### バックグラウンドと通知
- [ ] 作業中にホーム画面へ戻り、作業時間が過ぎると「作業時間が終わりました」の通知が届く
- [ ] 通知を受け取らずに休憩時間も過ぎた場合、続けて「休憩時間が終わりました」の通知も届く
- [ ] 作業時間を過ぎてからアプリを開くと、音楽が一時停止し、表示が正しいフェーズと残り時間になる
- [ ] 作業 → 休憩 → 作業の途中まで時間がたってから開くと、2回目の作業中として正しい残り時間が表示される
- [ ] 一時停止・スキップ・リセットをした後、古い時刻の通知が届かない
- [ ] 設定で時間を変えた後、変更が次のフェーズから反映され、通知もその時刻に届く
- [ ] **要実機検証**：画面ロック中・バックグラウンド中も音楽が鳴り続けるか（2-3 参照）

### フェーズ1の既知の制限
- アプリがバックグラウンドにある間はコードが動かないため、**作業時間が終わっても音楽は止まりません**。
  通知でお知らせし、アプリを開いた時点で一時停止します。フェーズ2の AlarmKit 連携で、通知上の停止ボタンから止められるようにする予定です。
- タイマーの状態はアプリを終了すると失われます（設定値は保存されます）。
- 選んだプレイリストはアプリを終了すると失われます。
