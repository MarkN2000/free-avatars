# Resonite向けCC0アバター配布仕様

## 目的

CC0のVRMアバターをResonite用の`.resonitepackage`に変換し、サムネイルとともにGitHubで配布する。

## 入力

- 配布元：PolygonalMind/100Avatars `v24.02.1`
- 対象：リリースに含まれるすべての`.vrm`
- 元VRMは成果物リポジトリには含めない
- 元VRMは`.work/sources/PolygonalMind-100Avatars-v24.02.1/`に配置する

## 変換

ローカル環境に用意した`ResoPon.exe`を使用する。実行ファイルの場所はリポジトリへ固定せず、`Invoke-ResoPon.ps1`の`-ResoPonPath`、環境変数`RESOPON_PATH`、または`PATH`から解決する。

- VRMごとに`.resonitepackage`を生成する
- ResoPonの設定は一括変換前に調整し、ユーザー確認済みの設定を使用する
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
├─ .work/
│  ├─ sources/
│  │  └─ PolygonalMind-100Avatars-v24.02.1/
│  ├─ staging/
│  └─ logs/
├─ avatars/
│  ├─ <avatar-name>/
│  │  ├─ avatar.resonitepackage
│  │  └─ thumbnail.webp
│  └─ ...
└─ tools/
   ├─ build.ps1
   ├─ Invoke-ResoPon.ps1
   ├─ Render-Thumbnails.ps1
   ├─ Render-VrmThumbnails.py
   ├─ Update-Catalog.ps1
   └─ Test-Repository.ps1
```

`<avatar-name>`には、VRMファイル名から拡張子を除いた名前を使用する。

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
  {"path":"avatars/100Avatars_001_Crimsom/avatar.resonitepackage","thumbnail":"avatars/100Avatars_001_Crimsom/thumbnail.webp"},
  {"path":"avatars/100Avatars_001_Voxel/avatar.resonitepackage","thumbnail":"avatars/100Avatars_001_Voxel/thumbnail.webp"}
]
```

規則：

- リポジトリルート基準の相対パスを使用する
- 区切り文字は`/`を使用する
- `path`の重複を禁止する
- `path`の昇順で並べる
- UTF-8で保存する
- クレジット、ID、ライセンス、ハッシュ、ファイルサイズなどは含めない

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

- 各アバターフォルダには`avatar.resonitepackage`と`thumbnail.webp`だけが存在する
- `.resonitepackage`が正常に生成されている
- `thumbnail.webp`が正常に表示でき、256×256pxである
- catalog内の全パスが実在する
- catalogに重複や未生成アバターがない
- すべての`.resonitepackage`がGit LFS管理されている
