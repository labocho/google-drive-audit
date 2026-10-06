# frozen_string_literal: true

require "fileutils"
require "googleauth"
require "googleauth/stores/file_token_store"
require "json"
require "launchy"
require "net/http"
require "signet/oauth_2/client"
require "socket"
require "timeout"
require "uri"
require "webrick"

module GoogleDriveAudit
  class Auth
    DEFAULT_SCOPE = "https://www.googleapis.com/auth/drive.metadata.readonly"
    OAuthClientConfig = Data.define(
      :kind,
      :client_id,
      :callback_uri,
      :registered_redirect_uris,
      :auth_uri,
      :token_uri
    )

    def initialize(client_secrets_path:, token_path:, scope: DEFAULT_SCOPE, callback_host: "localhost")
      @client_secrets_path = client_secrets_path
      @token_path = token_path
      @scope = scope
      @callback_host = callback_host
    end

    def credentials(user_id: "default")
      FileUtils.mkdir_p(File.dirname(token_path))
      config = oauth_client_config
      token_user_id = "#{user_id}:#{config.client_id.id}"
      authorizer = Google::Auth::UserAuthorizer.new(
        config.client_id,
        scope,
        token_store,
        callback_uri: config.callback_uri
      )
      credentials = authorizer.get_credentials(token_user_id)
      return credentials if credentials

      web_credentials(config, token_user_id)
    end

    private

    attr_reader :client_secrets_path, :token_path, :scope, :callback_host

    def oauth_client_config
      data = JSON.parse(File.read(client_secrets_path))
      client = data["web"]
      unless client && client["client_id"] && client["client_secret"]
        raise ArgumentError, "Web アプリケーションのOAuthクライアントJSONを指定してください: #{client_secrets_path}"
      end

      OAuthClientConfig.new(
        "web",
        Google::Auth::ClientId.new(client.fetch("client_id"), client.fetch("client_secret")),
        callback_uri_for(client),
        Array(client["redirect_uris"]),
        "https://accounts.google.com/o/oauth2/v2/auth",
        client["token_uri"] || "https://oauth2.googleapis.com/token"
      )
    rescue Errno::ENOENT
      raise ArgumentError, "OAuthクライアントJSONが見つかりません: #{client_secrets_path}"
    rescue JSON::ParserError => e
      raise ArgumentError, "OAuthクライアントJSONを解析できません: #{e.message}"
    end

    def callback_uri_for(client)
      redirect_uri = Array(client["redirect_uris"]).find { |uri| loopback_uri?(uri) }
      return redirect_uri if redirect_uri && explicit_port?(redirect_uri)

      CallbackReceiver::CALLBACK_PATH
    end

    def loopback_uri?(value)
      uri = URI.parse(value)
      uri.is_a?(URI::HTTP) && %w[localhost 127.0.0.1].include?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def explicit_port?(value)
      uri = URI.parse(value)
      uri.authority&.include?(":")
    rescue URI::InvalidURIError
      false
    end

    def token_store
      Google::Auth::Stores::FileTokenStore.new(file: token_path)
    end

    def web_credentials(config, token_user_id)
      callback = callback_receiver(config.callback_uri)
      oauth_client = Signet::OAuth2::Client.new(
        authorization_uri: config.auth_uri,
        token_credential_uri: config.token_uri,
        client_id: config.client_id.id,
        client_secret: config.client_id.secret,
        scope: Array(scope),
        redirect_uri: config.callback_uri
      )
      url = oauth_client.authorization_uri(
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: "true"
      ).to_s
      debug_auth_config(config: config, callback: callback, authorization_url: url)
      warn "OAuth認証URLを開きます。ブラウザで許可するとCLIへ自動で戻ります。"
      Launchy.open(url)
      warn "ブラウザが開かない場合は次のURLを開いてください:"
      warn url
      code = callback.wait_for_code
      warn "[auth-debug] received_code_length=#{code.length}" if auth_debug?
      oauth_client.code = code
      debug_token_exchange(oauth_client)
      token_hash = fetch_web_access_token(config: config, code: code)
      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: config.client_id.id,
        client_secret: config.client_id.secret,
        scope: Array(scope),
        access_token: token_hash.fetch("access_token"),
        refresh_token: token_hash["refresh_token"],
        expires_at: Time.now.to_i + token_hash.fetch("expires_in", 0).to_i
      )
      token_store.store(token_user_id, JSON.generate(
        client_id: credentials.client_id,
        access_token: credentials.access_token,
        refresh_token: credentials.refresh_token,
        scope: credentials.scope,
        expiration_time_millis: credentials.expires_at.to_i * 1000
      ))
      credentials
    ensure
      callback&.shutdown
    end

    def fetch_web_access_token(config:, code:)
      uri = URI.parse(config.token_uri)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.set_form_data(
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => config.callback_uri,
        "client_id" => config.client_id.id,
        "client_secret" => config.client_id.secret
      )
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      token_hash = JSON.parse(response.body)
      return token_hash if response.is_a?(Net::HTTPSuccess)

      raise Signet::AuthorizationError, "Authorization failed.  Server message:\n#{JSON.pretty_generate(token_hash)}"
    rescue JSON::ParserError
      raise Signet::AuthorizationError, "Authorization failed.  Server message:\n#{response&.body}"
    end

    def debug_auth_config(config:, callback:, authorization_url:)
      return unless auth_debug?

      redirect_uri = URI.parse(authorization_url).query&.then do |query|
        URI.decode_www_form(query).to_h["redirect_uri"]
      end
      warn "[auth-debug] client_id=#{config.client_id.id}"
      warn "[auth-debug] credential_kind=#{config.kind}"
      warn "[auth-debug] registered_redirect_uris=#{config.registered_redirect_uris.inspect}"
      warn "[auth-debug] callback_uri=#{config.callback_uri}"
      warn "[auth-debug] callback_base_url=#{callback.base_url}"
      warn "[auth-debug] authorization_redirect_uri=#{redirect_uri}"
      warn "[auth-debug] auth_uri=#{config.auth_uri}"
      warn "[auth-debug] token_uri=#{config.token_uri}"
      warn "[auth-debug] pkce=disabled"
    end

    def debug_token_exchange(oauth_client)
      return unless auth_debug?

      parameters = oauth_client.send(:generate_access_token_request).transform_values do |value|
        case value
        when nil
          nil
        else
          value.to_s
        end
      end
      redacted = parameters.merge(
        "code" => "[redacted length=#{parameters.fetch("code", "").length}]",
        "client_secret" => "[redacted length=#{parameters.fetch("client_secret", "").length}]"
      )
      warn "[auth-debug] token_request=#{redacted.inspect}"
    end

    def auth_debug?
      ENV["GDRIVE_AUDIT_DEBUG"] == "1"
    end

    def callback_receiver(callback_uri)
      CallbackReceiver.new(callback_uri: callback_uri, fallback_host: callback_host)
    end

    class CallbackReceiver
      CALLBACK_PATH = "/oauth2callback"
      TIMEOUT_SECONDS = 300

      attr_reader :base_url

      def initialize(callback_uri:, fallback_host:)
        @callback_uri = URI.parse(callback_uri)
        @host = @callback_uri.host || fallback_host
        @port = absolute_callback? ? @callback_uri.port : available_port
        @path = callback_path(@callback_uri.path)
        @base_url = "#{@callback_uri.scheme || "http"}://#{host}:#{port}"
        @queue = Queue.new
        @server = build_server
        @thread = Thread.new { server.start }
      end

      def wait_for_code
        Timeout.timeout(TIMEOUT_SECONDS) do
          result = queue.pop
          raise result.fetch(:error) if result[:error]

          result.fetch(:code)
        end
      rescue Timeout::Error
        raise "OAuth認証がタイムアウトしました"
      end

      def shutdown
        server.shutdown
        thread.join(2)
      end

      private

      attr_reader :host, :port, :path, :queue, :server, :thread

      def build_server
        WEBrick::HTTPServer.new(
          BindAddress: host,
          Port: port,
          AccessLog: [],
          Logger: WEBrick::Log.new(File::NULL)
        ).tap do |http|
          http.mount_proc path do |request, response|
            response.content_type = "text/plain; charset=utf-8"
            if request.query["code"]
              queue << { code: request.query.fetch("code") }
              response.status = 200
              response.body = "認証が完了しました。このタブを閉じてCLIに戻ってください。"
            else
              error = request.query["error"] || "認証コードを受け取れませんでした"
              queue << { error: error }
              response.status = 400
              response.body = "認証に失敗しました: #{error}"
            end
          end
        end
      end

      def callback_path(value)
        return CALLBACK_PATH if value.nil? || value.empty?

        value
      end

      def absolute_callback?
        @callback_uri.absolute?
      end

      def available_port
        TCPServer.open(host, 0) do |server|
          server.addr[1]
        end
      end
    end
  end
end
