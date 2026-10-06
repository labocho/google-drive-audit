# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/google_drive_audit/drive_scanner"

class DriveScannerTest < Minitest::Test
  def test_extract_id_from_folder_url
    url = "https://drive.google.com/drive/folders/abc123?usp=sharing"
    assert_equal "abc123", GoogleDriveAudit::DriveScanner.extract_id(url)
  end

  def test_extract_id_from_file_url
    url = "https://drive.google.com/file/d/file456/view"
    assert_equal "file456", GoogleDriveAudit::DriveScanner.extract_id(url)
  end

  def test_extract_id_leaves_plain_id
    assert_equal "plain-id", GoogleDriveAudit::DriveScanner.extract_id("plain-id")
  end
end
