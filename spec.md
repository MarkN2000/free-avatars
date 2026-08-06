# Resonite向けCC0アバター配布仕様

## 目的

CC0のVRMアバターをResonite用の`.resonitepackage`に変換し、サムネイルとともに配布する。GitHubリポジトリを成果物の正本および更新起点とし、一般利用者への配信にはCloudflare R2を使用する。

## 入力

- 配布元：PolygonalMind/100Avatars `v24.02.1`
- 対象：リリースに含まれるすべての`.vrm`
- 元VRMは成果物リポジトリには含めない
- 元VRMは`.work/sources/PolygonalMind-100Avatars-v24.02.1/`に配置する

## 変換

ローカル環境に用意した`ResoPon.exe`を使用する。実行ファイルの場所はリポジトリへ固定せず、`Invoke-ResoPon.ps1`の`-ResoPonPath`、環境変数`RESOPON_PATH`、または`PATH`から解決する。

- VRMごとに`.resonitepackage`を生成する
- アバターセットアップを有効にする
- Face Trackingを無効にする
- SimpleAvatarProtectionを無効にする
- Expression Menuを有効にする
- DefaultUserScaleを有効にし、DefaultScaleを`1`にする
- First Person Visibilityを無効にする
- Avatar Loading Displayを無効にする
- View Forwardを`0.18m`にする
- View Upを`0.1m`にする
- Near Clipを`0.14m`にする
- MToon Transparent材質は既定のCutoutとして変換する
- モデルインポートのタイムアウトを300秒にする
- 作業用一時ファイルを保持しない
- 親フォルダ名が`_Voxel`で終わるVRMだけ、すべてのアバターテクスチャのFilterModeをPointにする
- Voxel以外のVRMではテクスチャのFilterModeを変更しない
- 変換に失敗したアバターは配置およびcatalogへの登録を行わない
- 変換処理は自動化スクリプトから実行する

## ディレクトリ構成

```text
free-avatars/
├─ README.md
├─ LICENSE
├─ catalog.json
├─ .gitattributes
├─ .gitignore
├─ .github/
│  └─ workflows/
│     └─ deploy-r2.yml
├─ .work/
│  ├─ sources/
│  │  └─ PolygonalMind-100Avatars-v24.02.1/
│  ├─ staging/
│  └─ logs/
├─ avatars/
│  ├─ <avatar-name>/
│  │  ├─ <avatar-name>.<package-hash>.resonitepackage
│  │  └─ thumbnail.webp
│  └─ ...
└─ tools/
   ├─ build.ps1
   ├─ Invoke-ResoPon.ps1
   ├─ Render-Thumbnails.ps1
   ├─ Render-VrmThumbnails.py
   ├─ Publish-R2.ps1
   ├─ Update-Catalog.ps1
   └─ Test-Repository.ps1
```

`<avatar-name>`には、VRMファイル名から拡張子を除いた名前を使用する。

公開するResoniteパッケージのファイル名には`<avatar-name>.<package-hash>.resonitepackage`を使用する。全アバター共通の固定ファイル名は使用しない。

`<package-hash>`には、パッケージの実ファイル全体から計算したSHA-256の先頭8文字を小文字で使用する。パッケージを更新するとパッケージの公開URLが変わる。`thumbnail.webp`は`<avatar-name>`直下の固定パスとし、パッケージ更新時にURLを変更しない。

## 作業フォルダ

`.work/`は変換処理専用のローカル作業フォルダとする。

- `.work/sources/`：ダウンロード済みの変換元ファイル
- `.work/staging/`：ResoPonの一時出力
- `.work/logs/`：変換ログ

`.work/`全体を`.gitignore`でGit管理対象外にする。

```gitignore
/.work/
```

## サムネイル

VRMを3Dレンダリングして生成する。

- ファイル名：`thumbnail.webp`
- サイズ：256×256px
- 形式：WebP
- 品質：70
- 全アバターで画角、背景、照明を統一する
- モデル全体が収まるように自動調整する
- 元VRMの内蔵サムネイルには依存しない

## catalog.json

リポジトリルートに配置する。内容はJSON配列とし、各要素は`path`と`thumbnail`のみを持つ。

```json
[
  {"path":"avatars/100Avatars_001_Crimsom/100Avatars_001_Crimsom.<package-hash>.resonitepackage","thumbnail":"avatars/100Avatars_001_Crimsom/thumbnail.webp"},
  {"path":"avatars/001_Crimson/001_Crimson.<package-hash>.resonitepackage","thumbnail":"avatars/001_Crimson/thumbnail.webp"}
]
```

規則：

- リポジトリルート基準の相対パスを使用する
- 区切り文字は`/`を使用する
- `path`の重複を禁止する
- 通常アバターを先、Voxelアバターを後に並べる
- 各グループ内は`path`の昇順で並べる
- 現在のPolygonalMind由来データでは、フォルダ名が`3桁の番号_`で始まるものをVoxelアバターとして扱う
- UTF-8で保存する
- クレジット、ID、ライセンス、ハッシュの独立フィールド、ファイルサイズなどは含めない

## 公開・配信

Cloudflare R2の公開バケットへ、次の成果物だけをリポジトリと同じ相対パスで配置する。

```text
catalog.json
avatars/<avatar-name>/<avatar-name>.<package-hash>.resonitepackage
avatars/<avatar-name>/thumbnail.webp
```

公開URLにはCloudflareで管理するサブドメインを使用する。

```text
https://avatars.markn2000.com/catalog.json
https://avatars.markn2000.com/avatars/<avatar-name>/<avatar-name>.<package-hash>.resonitepackage
https://avatars.markn2000.com/avatars/<avatar-name>/thumbnail.webp
```

- `free-avatars`という名前のR2バケットへ`avatars.markn2000.com`をカスタムドメインとして接続する
- 本番配信に`r2.dev`、GitHub Raw、GitHub Pagesは使用しない
- `catalog.json`内のパスは、`https://avatars.markn2000.com/catalog.json`を基準に解決する
- R2上では`.resonitepackage`をGit LFSポインタではなく実ファイルとして配信する
- `catalog.json`は`application/json`、`thumbnail.webp`は`image/webp`、`.resonitepackage`は`application/octet-stream`として配信する
- `catalog.json`には`Cache-Control: no-cache`を設定し、更新確認時に再検証されるようにする
- 外部Webサイトから取得できるよう、公開バケットのCORSで任意のオリジンからの`GET`と`HEAD`を許可する
- 独自のキャッシュ規則は初期導入では追加せず、Cloudflareの既定動作を使用する

## 自動配信

GitHubの`main`ブランチを配信元とする。`avatars/`または`catalog.json`の変更が`main`へpushされたとき、GitHub ActionsからR2を更新する。初回配信や再実行には手動実行も使用できる。

処理順序：

1. Git LFSの実ファイルを含めてリポジトリをcheckoutする
2. `Test-Repository.ps1`でリポジトリ内の成果物とcatalogの整合性を検証する
3. `avatars/`が存在し、catalogが空ではなく、両者の件数が一致することを確認する
4. R2へ`avatars/`内の全ファイルを上書きアップロードする
5. R2の`catalog.json`を更新する
6. GitHub側に存在しなくなった`avatars/`内のファイルをR2から削除する

全成果物を毎回アップロードしてGitHubを正本とし、新しいハッシュ付きパッケージをcatalogより先に配置し、古いハッシュ付きパッケージをcatalog更新後に削除する。これにより、公開中のcatalogが未配置または削除済みのファイルを指す状態を避ける。

- 検証またはアップロードに失敗した場合は、catalogの更新と削除処理を行わない
- 自動削除の対象は専用R2バケット内の`avatars/`プレフィックスに限定する
- R2への書き込み権限は対象バケットだけに限定する
- CloudflareのアカウントID、R2アクセスキーID、R2シークレットアクセスキーはGitHub Actions Secretsに保存し、リポジトリへ記録しない
- 初期設定後のアバター追加、更新、削除および公開作業はGitHubへのpushだけで完結させる

## 導入計画

1. Cloudflare R2に`free-avatars`という名前の配信用専用バケットを作成する
2. `avatars.markn2000.com`をR2バケットのカスタムドメインとして接続する
3. 公開アクセス、CORS、配信用Content-Typeを設定する
4. 対象バケットだけに書き込めるR2認証情報を作成し、GitHub Actions Secretsへ登録する
5. リポジトリ検証、成果物アップロード、catalog更新、自動削除を行うGitHub Actions workflowを追加する
6. 初回配信後、catalog、サムネイル、パッケージを公開URLから取得できることを確認する
7. READMEの取得先を`https://avatars.markn2000.com/catalog.json`へ変更する

## Git LFS

`.resonitepackage`のみGit LFSで管理する。

```gitattributes
*.resonitepackage filter=lfs diff=lfs merge=lfs -text
```

以下は通常のGitで管理する。

- `catalog.json`
- `thumbnail.webp`
- `README.md`
- スクリプト

Git LFSはGitHub上の正本管理に使用する。GitHub ActionsではLFSオブジェクトを取得し、R2へ通常のオブジェクトとしてアップロードする。

`Update-Catalog.ps1`で成果物から`catalog.json`を再生成し、`Test-Repository.ps1`でディレクトリ内容、サムネイル寸法、catalogとの一致、Git LFS属性を検証する。

## README

READMEには以下を記載する。

- このリポジトリの目的
- Resoniteへのインポート方法
- PolygonalMind/100Avatarsへのクレジット
- 元リリース`v24.02.1`へのリンク
- CC0であること
- ResoPonで変換した非公式の派生配布物であること
- サムネイルはVRMから独自生成したこと

## 完了条件

- 各アバターフォルダ直下には`<avatar-name>.<package-hash>.resonitepackage`と`thumbnail.webp`だけが存在する
- `<package-hash>`がパッケージのSHA-256先頭8文字と一致する
- `.resonitepackage`が正常に生成されている
- `thumbnail.webp`が正常に表示でき、256×256pxである
- catalog内の全パスが実在する
- catalogに重複や未生成アバターがない
- すべての`.resonitepackage`がGit LFS管理されている
- GitHub Actionsの検証に成功した成果物だけがR2へ配信される
- `https://avatars.markn2000.com/catalog.json`を取得できる
- catalog内の`path`と`thumbnail`を公開URL基準で解決して取得できる
- 配信完了後のR2上の`avatars/`がGitHubリポジトリの内容と一致する
