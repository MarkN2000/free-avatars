# free-avatars

CC0で公開されているVRMアバターをResonite用の`.resonitepackage`に変換し、サムネイルとともに配布するリポジトリです。

## 収録内容

各アバターは次の2ファイルで構成します。

```text
avatars/<avatar-name>/avatar.resonitepackage
avatars/<avatar-name>/thumbnail.webp
```

`thumbnail.webp`はVRMをレンダリングして生成した256×256pxの画像です。

利用するアバターの`avatar.resonitepackage`をダウンロードし、Resoniteへインポートしてください。

ルートの`catalog.json`には、配布可能なアバターのパッケージとサムネイルの相対パスを収録しています。GitHub APIやGitHub Pagesを使わずに取得する場合は、次のRaw URLを使用できます。

```text
https://raw.githubusercontent.com/MarkN2000/free-avatars/<branch>/catalog.json
```

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

ResoPonによるパッケージ変換は、まず`.work/staging/packages/`へ出力します。既存の正常な出力はスキップされます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-ResoPon.ps1
```

サムネイルはBlenderで256×256pxのWebP（品質70）として`.work/staging/thumbnails/`へ生成します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Render-Thumbnails.ps1
```

両方の生成が完了したら、成功した成果物を`avatars/`へ配置し、catalogの更新と検証を行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

変換手順の詳細は[spec.md](spec.md)を参照してください。
