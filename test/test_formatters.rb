# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/google_drive_audit/activity_scanner"
require_relative "../lib/google_drive_audit/formatters"

class FormattersTest < Minitest::Test
  def test_csv_includes_move_parent_paths
    row = GoogleDriveAudit::ActivityScanner::ActivityRow.new(
      id: "file-id",
      name: "v1.0",
      mime_type: nil,
      modified_time: "2026-07-03T17:00:00+09:00",
      created_time: nil,
      web_view_link: "https://drive.google.com/open?id=file-id",
      last_modifying_user_email: "labocho@gmail.com",
      last_modifying_user_name: "labocho@gmail.com",
      path: "v1.0",
      action: "move",
      old_parent_path: "old-folder",
      new_parent_path: "new-folder",
      old_parent_url: "https://drive.google.com/open?id=old-id",
      new_parent_url: "https://drive.google.com/open?id=new-id"
    )

    csv = GoogleDriveAudit::Formatters.to_csv([row])

    assert_includes csv, "old_parent_path"
    assert_includes csv, "new_parent_path"
    assert_includes csv, "old_parent_url"
    assert_includes csv, "new_parent_url"
    assert_includes csv, "old-folder"
    assert_includes csv, "new-folder"
    assert_includes csv, "https://drive.google.com/open?id=old-id"
    assert_includes csv, "https://drive.google.com/open?id=new-id"
  end
end
