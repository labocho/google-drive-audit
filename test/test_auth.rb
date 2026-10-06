# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/google_drive_audit/auth"

class AuthTest < Minitest::Test
  def test_web_credentials_with_explicit_loopback_port_use_registered_redirect_uri
    Dir.mktmpdir do |dir|
      credentials_path = File.join(dir, "client_secret.json")
      File.write(credentials_path, JSON.generate(
        "web" => {
          "client_id" => "client-id",
          "client_secret" => "client-secret",
          "redirect_uris" => ["http://localhost:3000"]
        }
      ))
      auth = GoogleDriveAudit::Auth.new(
        client_secrets_path: credentials_path,
        token_path: File.join(dir, "tokens.yaml")
      )

      assert_equal "http://localhost:3000", auth.send(:oauth_client_config).callback_uri
    end
  end

  def test_credentials_without_explicit_port_use_relative_callback_path
    Dir.mktmpdir do |dir|
      credentials_path = File.join(dir, "client_secret.json")
      File.write(credentials_path, JSON.generate(
        "installed" => {
          "client_id" => "client-id",
          "client_secret" => "client-secret",
          "redirect_uris" => ["http://localhost"]
        }
      ))
      auth = GoogleDriveAudit::Auth.new(
        client_secrets_path: credentials_path,
        token_path: File.join(dir, "tokens.yaml")
      )

      assert_equal "/oauth2callback", auth.send(:oauth_client_config).callback_uri
    end
  end

  def test_code_verifier_length_is_valid_for_pkce
    auth = GoogleDriveAudit::Auth.new(
      client_secrets_path: "unused.json",
      token_path: "unused.yaml"
    )

    assert_includes 43..128, auth.send(:generate_code_verifier).length
  end
end
