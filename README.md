# free-avatars

CC0で公開されているVRMアバターをResonite用の`.resonitepackage`に変換し、サムネイルとともに配布するリポジトリです。

## 収録内容

各アバターは次の2ファイルで構成します。

```text
avatars/<avatar-name>/<package-hash>/avatar.resonitepackage
avatars/<avatar-name>/<package-hash>/thumbnail.webp
```

`<package-hash>`はパッケージ内容のSHA-256の先頭8文字です。パッケージを更新するとパスが変わるため、同じURLを再取得しないクライアントでも新しい成果物を取得できます。`thumbnail.webp`はVRMをレンダリングして生成した256×256pxの画像です。

利用するアバターの`avatar.resonitepackage`をダウンロードし、Resoniteへインポートしてください。

ルートの`catalog.json`には、配布可能なアバターのパッケージとサムネイルの相対パスを収録しています。公開データはCloudflare R2から取得できます。

```text
https://avatars.markn2000.com/catalog.json
```

`path`と`thumbnail`は、このcatalog URLを基準に解決してください。

## クレジットと権利

現在の変換元は[PolygonalMind/100Avatars](https://github.com/PolygonalMind/100Avatars)の[v24.02.1リリース](https://github.com/PolygonalMind/100Avatars/releases/tag/v24.02.1)です。同リリースはCC0で公開されています。

このリポジトリの配布物も[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)として公開します。変換後の`.resonitepackage`はResoPonを使用して生成し、サムネイルは元のVRMから独自に生成しています。

変換元VRMはこのリポジトリには含めません。

### 既知の除外

`100Avatars_051_Polybot.vrm`はResoniteのBipedRig生成時にエラーとなるため、配布対象から除外しています。同じデザインのVoxel版`051_Polybot.vrm`は収録しています。

## 開発

変換元VRMは次のGit管理対象外フォルダに配置します。

```text
.work/sources/PolygonalMind-100Avatars-v24.02.1/
```

catalogの更新と成果物の検証は次のコマンドで行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Update-Catalog.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-Repository.ps1
```

ResoPonによるパッケージ変換は、まず`.work/staging/packages/`へ出力します。既存の正常な出力はスキップされます。ResoPonの場所は引数で指定します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-ResoPon.ps1 -ResoPonPath "C:\path\to\ResoPon.exe"
```

毎回同じ場所を使用する場合は、環境変数`RESOPON_PATH`へ設定できます。`ResoPon.exe`が`PATH`上にある場合は指定不要です。

サムネイルはBlenderで256×256pxのWebP（品質70）として`.work/staging/thumbnails/`へ生成します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Render-Thumbnails.ps1
```

両方の生成が完了したら、成功した成果物を`avatars/`へ配置し、catalogの更新と検証を行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

既存アバターを更新するときは`-Force`を付け、古いハッシュフォルダを新しいものへ置き換えます。

変換手順の詳細は[spec.md](spec.md)を参照してください。

## 公開

GitHubの`main`ブランチを成果物の正本とします。`avatars/`または`catalog.json`を更新してpushすると、GitHub Actionsが内容を検証し、Cloudflare R2の`free-avatars`バケットへ自動反映します。GitHubから削除されたアバターは、catalog更新後にR2からも削除されます。

初回設定では、`avatars.markn2000.com`をR2バケットへ接続し、次のGitHub Actions Secretsを登録します。

- `CLOUDFLARE_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
