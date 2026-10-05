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
5. 完了済みで条件が一致するTool Cacheを再利用するか、Minilla releaseをHTTPSでdownloadする。
6. tarballをmanifestに記録されたSHA-256 digestで検証する。
7. bundled cpmを使用して、Minillaと依存関係をRunner Tool Cache内のstaging directoryへinstallする。
8. 生成された`minil` launcherを分離されたwrapperに置き換える。
9. install結果を公開して完了markerを書き出し、install先の`bin` directoryだけを`GITHUB_PATH`へ追加する。

## Runner Tool Cache

`@actions/tool-cache`で使用されているtool/version/architectureのdirectory構成と、隣接する完了markerに従います。

```text
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>/
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>.complete
```

たとえば`X64` runnerでMinilla `v3.2.0`をinstallする場合は、`minil/3.2.0/x64`を使用します。architectureは`x64`または`arm64`です。runner外などで`RUNNER_TOOL_CACHE`が未設定の場合は、`RUNNER_TEMP/setup-minil-tool-cache`へfallbackします。`RUNNER_TEMP`も未設定の場合はsystemの一時directoryを使用します。

完了marker、wrapper、元のscript、`installation-id`が存在し、記録された識別情報が現在のinstall条件と一致する場合のみ再利用します。識別情報には選択されたPerlのpath、version、`archname`、runner OSとarchitecture、Minilla tarballのdigest、解決mode、snapshotのdigest、bundled cpmのdigest、bootstrap cpanfileのdigest、installerのdigestを記録します。

未完了または条件が異なるentryは置き換えます。同じMinilla versionでもPerl環境が変わった場合に互換性のないinstall結果を再利用することはありません。各version/architectureのslotには1つの環境だけを保存します。self-hosted runnerでは同じTool Cache slotを並行job間で共有しないでください。

最終directoryに隣接するstaging directoryでinstallし、installとwrapperの検証が成功してから完了markerを書き出します。一時作業fileと失敗したstaging directoryは終了時に削除します。`actions/cache`のrestore/saveは行いません。

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

一時的にinstallしたCarton、download file、cpmの作業fileはAction終了時に削除します。Minillaのinstallが完了しなかった場合は、そのstaging directoryも削除します。正常に完了したMinillaのinstall先はRunner Tool Cacheに残します。

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
- Tool Cacheのdirectory構成、完了marker、再利用、無効化、install失敗時のcleanup
- fixture distributionに対する実際の`minil test`実行
