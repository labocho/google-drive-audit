# google-drive-audit

Google ドライブの指定フォルダ以下を再帰走査し、指定期間に指定ユーザが最終更新したディレクトリ / ファイルを一覧する Ruby CLI です。

## セットアップ

1. Google Cloud Console でプロジェクトを作成
2. 「API とサービス」→「ライブラリ」から Google Drive API, Google Drive Activity API を有効化
3. 「API とサービス」→「OAuth 同意画面」を設定し、「対象」→「テストユーザ」からテストユーザを追加
4. 「API とサービス」→「認証情報」→「認証情報を作成」→「OAuth クライアント ID」
  - アプリの種類は「ウェブアプリケーション」を選択
  - 承認済みのリダイレクト URI に`http://localhost:3000/oauth2callback` を設定
  - client secret (JSON) を取得して保存

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

初回実行時に OAuth 認証 URL がブラウザで開きます。認可後は `http://localhost:3000/oauth2callback` のローカルコールバックで CLI に自動復帰し、トークンは既定で `~/.config/google-drive-audit/tokens.yaml` に保存されます。保存先は `--token` で変更できます。

出力形式は `table`, `csv`, `json` です。ファイルだけを対象にしたい場合は `--files-only` を指定します。

## 取得できる変更

この CLI は Google Drive API v3 のファイルメタデータを使い、現在の `modifiedTime` と `lastModifyingUser` をもとに絞り込みます。加えて、Drive Activity API v2 を使って指定フォルダ配下の `MOVE` アクティビティも一覧します。移動履歴行では `old_parent_path` と `new_parent_path` に移動前後の親フォルダ名を出力します。親フォルダ名が取得できない場合、名前列は空になります。親フォルダIDが取得できる場合は `old_parent_url` と `new_parent_url` に Google Drive URL を出力します。

Drive Activity API で返される actor はメールアドレスではなく「現在の認証ユーザ」として表現される場合があります。そのため、移動履歴の検出は `--user` に指定したメールアドレスのアカウントで OAuth 認証している前提です。
