# 現行仕様

この文書では、現在の `setup-minil` の動作を説明します。

[English version](specification.md)

## 対応環境

- LinuxまたはmacOSを使用するGitHub Actions runner
- runnerから`X64`または`ARM64`として報告されるアーキテクチャ
- Perl 5.24以降
- Action実行前に`PATH`上で選択されているPerl実行ファイル

Windowsには対応していません。

## 公開インターフェース

composite Actionは1つのinputを受け取ります。

| Input | デフォルト | 説明 |
|---|---|---|
| `version` | `v3.2.0` | `manifests/minilla.json`に記載されたMinillaの正確なrelease |

1つのoutputを公開します。

| Output | 説明 |
|---|---|
| `version` | installされたMinillaのversion |

cache制御、digestのoverride、install先、依存関係の解決方法に関する診断情報は公開しません。

## install処理

Actionは1つのinstall stepで以下を実行します。

1. 選択されているPerl実行ファイルを絶対pathへ解決する。
2. Perlの正確なversionと`archname`を取得する。
3. 要求されたMinilla versionを`manifests/minilla.json`で検証する。
4. 利用可能であれば環境に完全一致する依存関係snapshotを選択する。
5. Minilla releaseをHTTPSでdownloadする。
6. tarballをmanifestに記録されたSHA-256 digestで検証する。
7. bundled cpmを使用して、Minillaと依存関係を`RUNNER_TEMP`配下の新しいdirectoryへinstallする。
8. 生成された`minil` launcherを分離されたwrapperに置き換える。
9. install先の`bin` directoryだけを`GITHUB_PATH`へ追加する。

install結果はRunner Tool Cacheや`actions/cache`には保存しません。Actionを呼び出すたびに新しいinstall先を作成します。

## Perl環境の分離

生成されるwrapperには、選択されたPerlの絶対pathを記録します。Minillaを起動するときだけ、install先の`lib/perl5` directoryを追加します。

Actionはjob全体の`PERL5LIB`を設定しないため、後続の無関係なstepでは呼び出し元のPerl環境が維持されます。

## releaseの完全性

対応するreleaseは`manifests/minilla.json`でallowlist管理します。各entryにはrelease URLと期待するSHA-256 digestを記録します。

Actionは呼び出し元からdigestを受け取りません。要求されたreleaseはrepositoryのmanifestに存在する必要があり、downloadしたtarballは必ずcommit済みのdigestと一致する必要があります。

## 依存関係snapshot

snapshotは次のdirectory形式で検索します。

```text
snapshots/<minilla-version>/<os>-<runner-arch>-perl-<perl-version>-<perl-archname>/
```

各path componentは小文字に変換し、`A-Z`、`a-z`、`0-9`、`_`、`.`、`-`以外の文字を`_`へ置き換えます。

各snapshot directoryには次のfileを配置します。

- `cpanfile`
- `cpanfile.snapshot`
- `environment.json`

`environment.json`には次の情報を記録します。

- runner OS
- runner architecture
- 正確なPerl version
- 正確なPerl `archname`
- Minilla version
- snapshot生成toolのmetadata

Actionは現在の環境からsnapshot pathを直接導出し、snapshotを使用する前にmetadataを検証します。独立したsnapshot indexは使用しません。

完全一致するdirectoryが存在しない場合、Actionはwarningを出力し、cpmでCPANから依存関係を動的に解決します。

## snapshot runtime

cpmがCarton形式のsnapshotを読み込むには`Carton::Snapshot`が必要です。そのためsnapshot modeでは、Minillaをinstallする前に`runtime/cpanfile`で指定された正確なCarton versionを一時作業directoryへinstallします。

Carton distributionのversionは固定します。Carton snapshot自体を読み込むparserをsnapshotからbootstrapすることはできないため、bootstrap時の依存関係は動的に解決します。

一時的にinstallしたCarton、download file、cpmの作業fileはAction終了時に削除します。Minillaのinstallが完了しなかった場合は、そのinstall先も削除します。正常に完了したMinillaのinstall先はjob終了まで`RUNNER_TEMP`配下に残します。

## bundled runtime

repositoryにはself-containedなcpmを`runtime/cpm`として同梱します。`runtime/manifest.json`にはcpmの取得元commitとSHA-256 digest、およびCartonのbootstrap要件を記録します。

`scripts/check-runtime`は次の項目を検証します。

- bundled cpmのdigest
- Cartonの正確な要求versionとcpanfileのdigest
- vendored Carton library treeやbootstrap snapshotがcommitされていないこと

`scripts/update-runtime`はbundled cpmとruntime manifestを更新します。

## snapshotの保守

`scripts/update-snapshots <version>`は次の処理を実行します。

1. 要求されたMinilla versionを検証する。
2. Carmelが利用できない場合は、bundled cpmでCarmelをinstallする。
3. 現在のsystem Perlを使用してCarton snapshotを生成する。
4. 正確な環境metadataを書き出す。
5. 同一環境のsnapshotを置き換える。
6. `scripts/check-snapshots`を実行する。

`.github/workflows/update-snapshots.yml`はGitHub-hosted UbuntuおよびmacOS runner上で、それぞれのimageに含まれるsystem Perlを使用してこの処理を実行します。生成された各snapshotを実際のMinilla installで検証し、snapshotをまとめたDraft PRを作成します。

## 継続的integration

CIでは次の項目を検証します。

- UbuntuおよびmacOSでのruntimeとsnapshot構造の検査
- UbuntuおよびmacOSで選択したPerlを使用するdynamic install
- GitHub-hosted UbuntuおよびmacOSのsystem Perlを使用するsnapshot生成とsnapshot-only install
- 未対応Minilla versionの拒否
- fixture distributionに対する実際の`minil test`実行
