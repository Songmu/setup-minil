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
| `version` | `runtime/manifest.json`の`minilla.version` | `vX.Y.Z`または`X.Y.Z`形式の正確なMinilla release |

1つのoutputを公開します。

| Output | 説明 |
|---|---|
| `version` | `vX.Y.Z`へ正規化したinstall済みMinillaのversion |

cache制御、digestのoverride、install先、依存関係の解決方法に関する診断情報は公開しません。

## install処理

Actionは1つのinstall stepで以下を実行します。

1. 選択されているPerl実行ファイルを絶対pathへ解決する。
2. Perlの正確なversionと`archname`を取得する。
3. 要求されたMinilla versionを正規化する。
4. 利用可能であれば環境に完全一致する依存関係snapshotを選択する。
5. 完了済みで条件が一致するTool Cacheがあれば再利用する。
6. それ以外の場合はMinillaの正確なversion要求と`runtime/minilla.cpanfile`の直接依存関係を含むcpanfileを生成し、bundled cpmを使用してTool Cacheの最終directoryへ直接installする。
7. 生成された`minil` launcherを分離されたwrapperに置き換える。
8. wrapperを検証して完了markerを書き出し、install先の`bin` directoryだけを`GITHUB_PATH`へ追加する。

## Runner Tool Cache

`@actions/tool-cache`で使用されているtool/version/architectureのdirectory構成と、隣接する完了markerに従います。

```text
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>/
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>.complete
```

たとえば`X64` runnerでMinilla `vX.Y.Z`をinstallする場合は、`minil/X.Y.Z/x64`を使用します。architectureは`x64`または`arm64`です。runner外などで`RUNNER_TOOL_CACHE`が未設定の場合は、`RUNNER_TEMP/setup-minil-tool-cache`へfallbackします。`RUNNER_TEMP`も未設定の場合はsystemの一時directoryを使用します。

完了marker、wrapper、元のscript、`installation-id`が存在し、記録された識別情報が現在のinstall条件と一致する場合のみ再利用します。識別情報には選択されたPerlのpath、version、`archname`、runner OSとarchitecture、Minilla version、解決mode、snapshotのdigest、bundled cpmのdigest、bootstrap cpanfileのdigest、推奨依存関係cpanfile、installer、共通moduleのdigestを記録します。

未完了または条件が異なるentryは置き換えます。同じMinilla versionでもPerl環境が変わった場合に互換性のないinstall結果を再利用することはありません。各version/architectureのslotには1つの環境だけを保存します。self-hosted runnerでは同じTool Cache slotを並行job間で共有しないでください。

最終directoryへ直接installするため、installされたmoduleがdirectoryの移動に対応している必要はありません。installとwrapperの検証が成功してから完了markerを書き出します。一時作業fileと失敗したinstall結果は終了時に削除します。`actions/cache`のrestore/saveは行いません。

## 推奨依存関係

`runtime/minilla.cpanfile`にはMinillaのdist・release commandで使用する推奨moduleを記載します。現在の一覧は選択したMinilla releaseのruntime推奨依存関係に合わせており、repository内で保守します。これらのmoduleは直接の`requires`として宣言し、cpmの再帰的な推奨依存関係処理に頼らずinstallします。
また、Minillaのデフォルトbuild backendである`Module::Build::Tiny`を明示的に要求し、`minil test`と`minil dist`が事前installに依存しないようにします。

最上位のcpanfileにMinillaの正確なversion要求とこれらの直接依存関係をまとめることで、cpmを1回呼び出してinstallします。Action自身でMinillaのmetadataをdownload・展開することはありません。

これには`Software::License`、`Version::Next`、`CPAN::Uploader`、Minillaが推奨するrelease test用moduleが含まれます。これらのmoduleの`requires`は通常どおり解決しますが、各module自身の`recommends`やMinillaの`suggests`を再帰的に有効にはしません。

## Perl環境の分離

生成されるwrapperには、選択されたPerlの絶対pathを記録します。Minillaを起動するときだけ、install先の`lib/perl5` directoryを追加します。

Actionはjob全体の`PERL5LIB`を設定しないため、後続の無関係なstepでは呼び出し元のPerl環境が維持されます。

## versionの選択

inputが省略された場合や空の場合は、`runtime/manifest.json`の`minilla.version`を使用します。この値は`vX.Y.Z`形式の正確なreleaseである必要があります。inputを明示した場合はmanifestのデフォルトより優先します。

inputは先頭の`v`の有無を問わず、3つの数値からなる正確なversionを受け付けます。要求されたMinilla versionはcpmがCPANから解決します。該当releaseが見つからない場合やinstallできない場合はActionを失敗させます。

Actionではreleaseのallowlist管理、tarballの直接download、独自のrelease digest検証は行いません。downloadと依存関係の解決はcpmへ委ねます。

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

`scripts/check-snapshots`はこの階層にあるsnapshot候補directoryをすべて検査します。`environment.json`がないdirectoryも対象にし、3つのfileが揃っていることを確認します。

`environment.json`には次の情報を記録します。

- runner OS
- runner architecture
- 正確なPerl version
- 正確なPerl `archname`
- Minilla version
- snapshot生成toolのmetadata

Actionは現在の環境からsnapshot pathを直接導出し、snapshotを使用する前にmetadataを検証します。独立したsnapshot indexは使用しません。

完全一致するdirectoryが存在しない場合、Actionはwarningを出力し、cpmでCPANから依存関係を動的に解決します。

CartonのbootstrapとMinillaのinstallでは、cpmを呼び出しごとの一時作業directory内で実行し、利用者の`cpanfile.snapshot`を読み込まないようにします。

## snapshot runtime

cpmがCarton形式のsnapshotを読み込むには`Carton::Snapshot`が必要です。そのためsnapshot modeでは、Minillaをinstallする前に`runtime/cpanfile`で指定された正確なCarton versionを一時作業directoryへinstallします。

Carton distributionのversionは固定します。Carton snapshot自体を読み込むparserをsnapshotからbootstrapすることはできないため、bootstrap時の依存関係は動的に解決します。

一時的にinstallしたCartonとcpmの作業fileはAction終了時に削除します。Minillaのinstallが完了しなかった場合は、そのinstall先も削除します。正常に完了したMinillaのinstall先はRunner Tool Cacheに残します。

## bundled runtime

repositoryにはself-containedなcpmを`runtime/cpm`として同梱します。`runtime/manifest.json`にはMinillaのデフォルトreleaseを定義し、cpmの取得元commitとSHA-256 digest、およびCartonのbootstrap要件を記録します。

`scripts/check-runtime`は次の項目を検証します。

- bundled cpmのdigest
- Minillaのデフォルトversionの形式
- Cartonの正確な要求versionとcpanfileのdigest
- vendored Carton library treeやbootstrap snapshotがcommitされていないこと

`scripts/update-runtime`はbundled cpmとruntime manifestを更新します。

## snapshotの保守

`scripts/update-snapshots <version>`は次の処理を実行します。

1. 要求されたMinilla versionを正規化する。
2. 選択したPerlとbundled cpmを使用して、毎回一時local-libへCarmelをinstallする。PATH上の既存Carmelは再利用せず、同じPerlを指定して起動する。
3. Minillaの正確なversionと`runtime/minilla.cpanfile`の直接依存関係を含むcpanfileを生成し、Carmelがsnapshotに含めるようにする。
4. 現在のsystem Perlを使用してCarton snapshotを生成する。
5. 正確な環境metadataを書き出す。
6. 同一環境のsnapshotを置き換える。
7. `scripts/check-snapshots`を実行する。

`.github/workflows/update-snapshots.yml`はGitHub-hosted UbuntuおよびmacOS runner上で、それぞれのimageに含まれるsystem Perlを使用してこの処理を実行します。生成された各snapshotを実際のMinilla installで検証し、手動実行時はsnapshotをまとめたDraft PRを作成します。手動実行ではdispatchで選択したbranchに関係なくdefault branchを使用し、同じdefault branchをPRのbaseとします。すべてのjobは生成前に確定した同一のsource commitを使用します。

workflowのversion inputを省略した場合は、checkoutしたmanifestの`minilla.version`を使用します。解決したversionはsnapshotの検証とPR作成にも引き継ぎます。

## 依存関係の更新

`.github/renovate.json5`でRenovateを設定し、`runtime/manifest.json`のMinillaのデフォルトrelease、`runtime/cpanfile`のCarton要件、`runtime/manifest.json`のbundled cpmのtagとcommitを更新します。cpm更新workflowはcpmの項目が変わった場合にのみ、同梱実行ファイルとchecksumを更新します。
同一repositoryのRenovate PRがMinillaのデフォルトversionと対象releaseのsnapshotだけを変更する場合、snapshot workflowはPRのhead commitからUbuntuおよびmacOSのsnapshotを生成・検証します。snapshotをまとめて同じPR branchへcommitし、CIを起動します。他のruntime項目や無関係なfileの変更は拒否し、Minillaのデフォルトversionが変わらないPRでは生成をskipします。過去のreleaseのsnapshotは保持します。

## 開発

```sh
make test
make integration
```

`make test`はruntime、snapshot、scriptの検査後、`prove -v t`でoffline回帰testを実行します。`prove -v t`を直接実行することもできます。`make integration`は同じ検査後に`t/smoke.sh`を実行し、実際のMinilla installとdistribution commandを検証します。

installerと保守scriptは選択したPerlのcore moduleを使用します。`t/`のoffline回帰testでは共通のcpm fixtureを使用し、integration検査ではlocalとCIで同じMinilla distribution fixtureを使用します。

## release

releaseはtagprで準備します。release PRをmergeするとSemVer tagとGitHub Releaseが作成され、`.github/workflows/tagpr.yml`がmajor-version tag（現在は`v0`）を新しいreleaseへ移動します。

Actionは移動するmajor-version tag、正確なrelease tag、完全なcommit SHAで参照できます。再現可能なworkflowのためには、完全なcommit SHAでの固定を推奨します。

## 継続的integration

CIでは次の項目を検証します。

- UbuntuおよびmacOSでのruntimeとsnapshot構造の検査
- UbuntuおよびmacOSで選択したPerlを使用するdynamic install
- GitHub-hosted UbuntuおよびmacOSのsystem Perlを使用するsnapshot生成とsnapshot-only install
- UbuntuおよびmacOSでcommit済みsnapshotを再生成せずに使用するsnapshot-only install。system Perl環境の完全一致と、追跡対象のsnapshotファイルが変更されていないことも確認する
- 不正なversion形式の拒否
- Tool Cacheのdirectory構成、完了marker、再利用、無効化、install失敗時のcleanup
- MIT licenseのfixture distributionに対する実際の`minil test`と`minil dist`の実行、およびtest結果と生成archiveの確認
