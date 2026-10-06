# google-drive-audit

Google ドライブの指定フォルダ以下を再帰走査し、指定期間に指定ユーザが最終更新したディレクトリ / ファイルを一覧する Ruby CLI です。

## セットアップ

1. Google Cloud で OAuth クライアント ID を作成します。
   - 種類: デスクトップアプリ
   - 有効にする API: Google Drive API
2. クライアント JSON をダウンロードします。
3. 依存 gem をインストールします。

```sh
bundle install
chmod +x bin/gdrive-audit
```

## 使い方

```sh
bin/gdrive-audit \
  --root "https://drive.google.com/drive/folders/FOLDER_ID" \
  --from "2026-10-01T00:00:00+09:00" \
  --to "2026-10-06T23:59:59+09:00" \
  --user "user@example.com" \
  --credentials "./client_secret.json" \
  --format csv
```

初回実行時に OAuth 認証 URL がブラウザで開きます。認可後はローカルの一時コールバックで CLI に自動復帰し、トークンは既定で `~/.config/google-drive-audit/tokens.yaml` に保存されます。保存先は `--token` で変更できます。

Google API Ruby Client の公式 CLI サンプルと同じ、認証コードを貼り付ける方式を使いたい場合は `--manual-auth` を指定します。

```sh
bin/gdrive-audit \
  --root "https://drive.google.com/drive/folders/FOLDER_ID" \
  --from "2026-10-01T00:00:00+09:00" \
  --to "2026-10-06T23:59:59+09:00" \
  --user "user@example.com" \
  --credentials "./client_secret.json" \
  --format csv \
  --manual-auth
```

出力形式は `table`, `csv`, `json` です。ファイルだけを対象にしたい場合は `--files-only` を指定します。

## 取得できる変更

この CLI は Google Drive API v3 のファイルメタデータを使い、現在の `modifiedTime` と `lastModifyingUser` をもとに絞り込みます。過去のすべての編集イベントや閲覧履歴の監査ログを取得するものではありません。
