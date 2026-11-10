# Apple File System Case Sensitivity Tester

iPhone・iPad・Macの保存先ごとに、ファイルシステムのAPI属性と実ファイルの作成結果を比較するSwiftUIアプリです。OS名から大文字・小文字の区別を推測しません。アプリの利用に外部ライブラリ・アカウント・管理者権限は不要です。iPhone / iPadへの開発用インストールにはApple Accountによる署名設定が必要です。

## プロジェクト構成

```text
CaseSensitivityTester.xcodeproj/  iOS / macOSの独立したアプリターゲットと共有Scheme
Config/                          共有ビルド設定とローカル署名設定のサンプル
Shared/                          Foundation / POSIX検証・判定・モデル・レポート出力
SharedUI/                        非同期実行・履歴保存・共通結果表示・JSON読み込み
iOS/                            iPhone / iPadのUIと共有シート
macOS/                           NSOpenPanel / NSSavePanelとサンドボックス設定
Tests/Unit/                      モック可能な判定・エラー・シリアライズのXCTest
Tests/Integration/               実ファイルを使うXCTest
Package.swift                    共通ロジックだけをビルド・テストするSwift Package
Tools/generate_project.py        Xcodeプロジェクトの再生成（Python標準ライブラリのみ）
```

両アプリは同じ `Shared/` と `SharedUI/` のソースを直接コンパイルします。Swift Packageはテストのための別の入口です。アプリビルド時にPackageの解決やPythonの実行は不要です。

## ビルド要件

- Xcode 27.2 / Swift 6.4.2で確認。Swift言語モードは5、Strict ConcurrencyはComplete。
- 最小OS: iOS / iPadOS 16、macOS 13。
- iOSターゲット: iPhone・iPad（Device Family 1, 2）。Mac Catalystは対象外。
- macOSターゲット: Apple Silicon (`arm64`)・Intel (`x86_64`)。ReleaseではUniversal Binaryをビルドできます。
- 実機へのインストールには、必要に応じて自分のApple Development Teamと署名を設定してください。

Bundle Identifier:

| ターゲット / Scheme | Bundle Identifier |
| --- | --- |
| `CaseSensitivityTester-iOS` | `io.github.watr.CaseSensitivityTester.iOS` |
| `CaseSensitivityTester-macOS` | `io.github.watr.CaseSensitivityTester.macOS` |

Team IDはGit管理外の `Config/Signing.local.xcconfig` に分離します。初回設定は次の手順です。

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

作成したファイルの `DEVELOPMENT_TEAM =` の右側に自分のTeam IDを設定してください。iOSのDebug / Release両方が `Config/iOS.xcconfig` 経由で読み込みます。ローカルファイルがなくても、Simulatorや署名なしのビルドは可能です。Xcodeプロジェクトを再生成してもローカルファイルは変更されません。

XcodeのSigning画面でTeamを選び直すと `project.pbxproj` にTeam IDが直接書き込まれることがあります。Team IDや証明書・プロビジョニングの個別設定はローカルファイルに記載し、コミット前にプロジェクト差分を確認してください。Apple Account・証明書・プロビジョニング自体はXcode / Keychain側で管理します。

Identifierを変更する場合はXcodeの設定と `Tools/generate_project.py` の両方を更新してください。再生成は `python3 Tools/generate_project.py` です。

## iPhone / iPadでのビルド・インストール

1. `CaseSensitivityTester.xcodeproj` をXcodeで開きます。
2. Xcodeの **Settings → Apple Accounts** で必要なアカウントを設定し、上記のローカル設定ファイルにTeam IDを記入します。iOSターゲットの **Signing & Capabilities** でAutomatically manage signingが有効なことを確認します。必要ならBundle Identifierを自分のものに変更します。
3. Schemeを `CaseSensitivityTester-iOS`、実行先を接続したiPhoneまたはiPadにします。端末のDeveloper Modeや信頼設定はXcodeの案内に従います。
4. Runでインストール・起動します。
5. 「検証開始 / 再検証」を押し、Documents / Application Support / Temporary Directoryの結果を確認します。
6. 「JSONを共有」「テキストを共有」から共有シートを開き、ファイル保存や転送を行います。

これら3つの検証先はアプリのサンドボックス内です。ユーザーの一般のDocumentsフォルダではありません。iOSの任意フォルダを検証先として選ぶ追加機能は未実装です。JSONレポートの読み込みにはファイル選択を使用できます。

署名なしでコンパイルのみを確認するコマンド:

```sh
xcodebuild -project CaseSensitivityTester.xcodeproj \
  -scheme CaseSensitivityTester-iOS -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/case-ios CODE_SIGNING_ALLOWED=NO build
```

署名なしの成果物は実機にインストールできません。Simulatorの結果はホスト側ストレージの特性に影響されるため、iPhone / iPad実機の結果とは区別してください。

## Macでのビルド・起動

1. Xcodeでプロジェクトを開き、Schemeを `CaseSensitivityTester-macOS` にします。
2. Teamを設定し、実行先をMy MacにしてRunします。
3. デフォルトの3つの保存先を検証します。
4. 「フォルダを追加…」で任意のディレクトリを選択します。複数選択・複数回の追加が可能です。
5. 再検証すると、選択した保存先も個別に検証されます。
6. 「JSONを保存…」「テキストを保存…」から保存できます。

Universal Binaryのコンパイル確認:

```sh
xcodebuild -project CaseSensitivityTester.xcodeproj \
  -scheme CaseSensitivityTester-macOS -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/case-mac CODE_SIGNING_ALLOWED=NO \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

### サンドボックス・ファイルアクセス

macOSはApp Sandboxと `com.apple.security.files.user-selected.read-write` を有効にしています。ネットワーク用のentitlementは付けていません。標準のDocuments・Application Support・Temporary Directoryはコンテナ内の領域です。

任意フォルダはNSOpenPanelで許可されたURLを保持します。security-scopedアクセスの開始に成功したURLは、対象削除時またはモデル破棄時に終了します。開始がfalseでも既にOpen Panelによって許可されている場合があるため、それだけで拒否とは判定せず、実際のファイル操作で確認します。選択したフォルダのアクセス権はアプリ終了後に復元しません。次回起動時は再選択してください。

書き込み・読み取り・一覧取得・同期・削除に失敗した場合は実測をInconclusiveにします。対象フォルダの既存ファイルを書き込み確認に使うことはありません。

### 外付けSSD・別ボリュームの検証

Finder等でボリュームをマウントし、「フォルダを追加…」でその中の書き込み可能なフォルダを選びます。内蔵SSD、別のAPFSボリューム、exFAT、ネットワーク共有を同じ手順で追加できます。ボリュームごとにAPIを取得し直します。フォーマットの変更はしません。

アプリ自身はネットワークAPIを使用しません。ネットワーク共有を選んだ場合、そのファイル操作に必要な通信はOSのファイルシステムによって行われます。

## 結果の読み方

| 表示 | 意味 |
| --- | --- |
| Case-sensitive | 大文字・小文字を区別する |
| Case-insensitive | 大文字・小文字を区別しない |
| Inconclusive | エラー・不整合等があり確定できない |
| Unknown | API属性が取得できず不明（Boolのnil） |

APIは `volumeSupportsCaseSensitiveNamesKey` のtrue / false / nilを表示します。大小文字を保持する属性の公開API名は **`volumeSupportsCasePreservedNamesKey`** です（仕様書のPreservingに相当）。Case-preservingはCase-sensitiveとは独立の属性です。属性は一つずつ取得し、一部の取得失敗で他の属性を捨てないようにしています。

実測は対象内に `CaseSensitivityTester-<UUID>` を作成し、次を実行します。

- `Test.txt` に `UPPER_FILE_CONTENT` を書き込みます。
- `test.txt` に `lower_file_content` を書き込みます。
- 両方ともPOSIX `openat()` の `O_WRONLY | O_CREAT | O_EXCL` を使用します。これは対象ディレクトリ記述子を指定する `open()` 系APIです。既存ファイルは上書きしません。
- 部分書き込みとEINTRを処理し、fsync・closeの失敗も記録します。
- エントリ一覧、読み取り内容、`fstatat()`によるinodeとdevice IDを照合します。これはディレクトリ記述子を指定する `stat()` 系APIです。シンボリックリンクは追跡しません。

Case-sensitiveには両方の作成成功、正確な2エントリ、期待する別々の内容、同じデバイス上の異なるinodeが必要です。Case-insensitiveには2つ目のEEXIST、正確な1エントリ、両名で同じ期待内容・inode・デバイスを参照する証拠が必要です。EEXISTだけでは確定しません。

APIと実測は別々に保存します。APIがUnknownでも実測が完全なら実測の判定を使用します。APIと実測が矛盾する場合、最終判定はInconclusiveとなり、エラーにも矛盾を記録します。

### 安全なクリーンアップ

作成したファイルだけをディレクトリ記述子相対の `unlinkat()` で削除します。UUIDディレクトリのinode・デバイスを再確認した後、空のディレクトリとして削除します。**検証処理では再帰削除を行いません。** 予期しないエントリがある場合は残してエラーを記録します。親ディレクトリや既存ファイルは削除しません。

## 履歴・OS間の比較・共有

結果は端末内のApplication Support配下の `CaseSensitivityTester/history.json` に自動保存され、直近100件を表示します。「JSONを読み込み・比較…」で別の端末が書き出したレポートを複数選択すると、その結果を同じ一覧で比較できます。同じ結果IDは重複させません。保存・共有の対象は一覧にある全履歴です。

比較するときは、platform・model・OSバージョン・保存先・ボリューム・APIと実測の3判定を確認してください。読み込んだJSONの判定は、保存済みの判定文字列ではなく証拠から再計算します。読み込みはこのアプリの配列形式のみ、1ファイル5 MB以下に対応します。

履歴と詳細ログには絶対パス等を保持します。共有・保存の既定値ではパス、ボリューム名、パスを含む可能性のあるエラー本文を伏せます。「絶対パス・ボリューム名を含める」を選ぶと確認ダイアログを表示します。詳細ログで内容を確認してから共有してください。伏せ字で出力したレポートから元のパス・エラー本文は復元できません。

## JSON仕様

UTF-8のJSON配列です。各要素が1保存先・1回分の検証を表します。日付はISO 8601、inodeはUInt64、device IDはInt64です。

| キー | 内容 |
| --- | --- |
| `id` | 検証結果のUUID |
| `device` | platform、実行時取得のハードウェアmodel・OS、appVersion、buildNumber、testVersion |
| `test` | timestamp、directory、label、volumeName |
| `api` | caseSensitive、casePreserving、volumeName、volumeURL、fileSystemAttributes、fileSystemID、errors |
| `actualTest.first` / `second` | created、createErrno、content、inode、deviceID |
| `actualTest` | firstFileCreated、secondFileCreated、entries、contentsVerified、differentInodes、independentFiles、cleanupSucceeded、temporaryDirectory、verdict、errors |
| `finalVerdict` | APIと実測を照合した最終結果 |
| `errors` | API・実測のエラーと判定の矛盾 |

`api.caseSensitive` / `casePreserving` のUnknownはnullです。未実施の作成結果や検証フラグもnullです。ファイル証拠内の未取得のoptionalフィールドは省略される場合があります。`createErrno` はopen成功時0、失敗時は直後のerrnoです。書き込み・読み取り・close等のエラーは操作名とerrnoを `actualTest.errors` に残します。

`fileSystemAttributes` はFoundationが返すキーと値の診断用文字列表現です。`fileSystemID` は `fstatfs()` の `f_fsid` の2つの値をコロン区切りで表した文字列です。inode・device ID・File System IDを、再起動や再マウントをまたぐ永続的な識別子として使用しないでください。テキストレポートには判定サマリと完全なJSONを含めます。

## 自動テスト

```sh
swift test
swift test --filter CoreUnitTests
swift test --filter CoreIntegrationTests
```

共通ロジックは `FileProbing` による差し替えと、証拠データを入力とする `VerdictResolver` の単体テストに対応します。単体テストでは両判定、EEXISTだけでは判定しないこと、権限・I/Oエラー、内容・inodeの不整合、API矛盾、Unknown、JSON往復、伏せ字を確認します。統合テストは別ターゲットで、実ファイル検証・クリーンアップ・既存ファイル保護・存在しない保存先等を確認します。

Xcodeでテストする場合は `Package.swift` を別途開き、パッケージのテストを実行してください。アプリの2つのSchemeはビルド・実行用です。

## 確認状況と既知の制約

2026-11-10の確認結果（Xcode 27.2 / Swift 6.4.2）:

| 確認項目 | 結果 |
| --- | --- |
| iOS / iPadOS実機向けReleaseビルド（署名なし） | 成功 |
| macOS Release Universalビルド（アドホック署名） | 成功、arm64 / x86_64を確認 |
| 共通ロジックの単体テスト | 10件成功 |
| 実ファイルの統合テスト | 4件成功（権限エラー・既存ファイル保護・クリーンアップを含む） |
| Mac上の2保存先の共通ロジック実測 | いずれもAPI・実測がCase-insensitiveで一致、削除成功、エラーなし |
| 成果物のBundle Identifier | 両ターゲットで `io.github.watr` プレフィックスを確認 |

- macOSのUI操作（フォルダ選択・保存ダイアログ）とiOS共有シートの操作は未検証です。
- iPhone / iPad実機へのインストール・実測、Intel実機での実行、外付けSSD・exFAT・ネットワーク共有での実測は未検証です。署名・プロビジョニングも利用者の環境での確認が必要です。
- 2つのASCIIファイル名だけを検証します。Unicode正規化・言語別の大小文字規則・すべての名前の振る舞いを網羅するものではありません。
- ファイルシステムの属性・inodeが取得できない保存先、アクセス権やプロバイダの制限がある保存先はInconclusiveになる場合があります。APIのnilをOS名やフォーマット名で補完しません。
- ネットワーク共有や取り外された保存先でI/Oが遅延した場合、バックグラウンド処理の完了を待ちます。強制的なタイムアウトはありません。
- アプリ強制終了・端末切断・クリーンアップ失敗時には専用ディレクトリが残る場合があります。結果の `temporaryDirectory` と対象パスを確認し、必要なら利用者が削除してください。起動時の一括削除は行いません。
- 履歴の一覧・比較は端末内のみです。クラウド同期は行いません。
- App Store配布用のアイコン・公開署名・notarizationは含みません。

API参考: [大小文字の区別を示すボリューム属性](https://developer.apple.com/documentation/foundation/urlresourcekey/volumesupportscasesensitivenameskey)、[macOS App Sandboxのファイルアクセス](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)、[security-scopedアクセス](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())。
