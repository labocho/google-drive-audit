# frozen_string_literal: true

require "optparse"
require "pathname"

require_relative "audit"
require_relative "auth"
require_relative "drive_scanner"
require_relative "formatters"
require_relative "version"

module GoogleDriveAudit
  class CLI
    DEFAULT_TOKEN_PATH = File.expand_path("~/.config/google-drive-audit/tokens.yaml")

    def initialize(argv)
      @argv = argv
      @options = {
        format: "table",
        token: DEFAULT_TOKEN_PATH,
        include_folders: true,
        manual_auth: false
      }
    end

    def run
      parser.parse!(argv)
      validate!

      credentials = Auth.new(
        client_secrets_path: options.fetch(:credentials),
        token_path: options.fetch(:token),
        manual: options.fetch(:manual_auth)
      ).credentials
      scanner = DriveScanner.new(credentials: credentials)
      audit = Audit.new(
        scanner: scanner,
        from: options.fetch(:from),
        to: options.fetch(:to),
        user_email: options.fetch(:user),
        include_folders: options.fetch(:include_folders)
      )
      root_id = DriveScanner.extract_id(options.fetch(:root))
      rows = audit.rows(root_id)
      Formatters.write(rows, format: options.fetch(:format))
    rescue OptionParser::ParseError, ArgumentError => e
      warn e.message
      warn e.backtrace.join("\n") if ENV["GDRIVE_AUDIT_DEBUG"]
      warn parser
      exit 1
    rescue Google::Apis::AuthorizationError => e
      warn "Google APIの認可に失敗しました: #{e.message}"
      exit 1
    rescue Signet::AuthorizationError => e
      warn "OAuth認証コードの交換に失敗しました: #{e.message}"
      warn "ブラウザで開いた古い認可URLは再利用できません。もう一度コマンドを実行してください。"
      exit 1
    rescue Google::Apis::ClientError, Google::Apis::ServerError => e
      warn "Google Drive APIエラー: #{e.message}"
      exit 1
    end

    private

    attr_reader :argv, :options

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: gdrive-audit --root FOLDER_ID_OR_URL --from ISO8601 --to ISO8601 --user EMAIL --credentials client_secret.json [options]"

        opts.on("--root VALUE", "走査するGoogle DriveフォルダIDまたはURL") { |value| options[:root] = value }
        opts.on("--from ISO8601", "開始日時。例: 2026-10-01T00:00:00+09:00") { |value| options[:from] = value }
        opts.on("--to ISO8601", "終了日時。例: 2026-10-06T23:59:59+09:00") { |value| options[:to] = value }
        opts.on("--user EMAIL", "変更ユーザのメールアドレス") { |value| options[:user] = value }
        opts.on("--credentials PATH", "OAuthクライアントJSONのパス") { |value| options[:credentials] = value }
        opts.on("--token PATH", "OAuthトークン保存先。既定: #{DEFAULT_TOKEN_PATH}") { |value| options[:token] = value }
        opts.on("--format FORMAT", "出力形式: table, csv, json") { |value| options[:format] = value }
        opts.on("--files-only", "フォルダを出力対象から除外する") { options[:include_folders] = false }
        opts.on("--manual-auth", "公式サンプルと同じ認証コード貼り付け方式を使う") { options[:manual_auth] = true }
        opts.on("-v", "--version", "バージョンを表示する") do
          puts VERSION
          exit
        end
        opts.on("-h", "--help", "ヘルプを表示する") do
          puts opts
          exit
        end
      end
    end

    def validate!
      %i[root from to user credentials].each do |key|
        raise OptionParser::MissingArgument, "--#{key.to_s.tr("_", "-")} は必須です" if blank?(options[key])
      end

      raise ArgumentError, "--credentials が見つかりません: #{options[:credentials]}" unless Pathname(options[:credentials]).file?
      raise ArgumentError, "--format は table, csv, json のいずれかです" unless %w[table csv json].include?(options[:format])
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end
  end
end
