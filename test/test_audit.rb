# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/google_drive_audit/audit"
require_relative "../lib/google_drive_audit/drive_scanner"

class AuditTest < Minitest::Test
  Item = GoogleDriveAudit::DriveScanner::Item

  def test_rows_filters_by_time_and_user
    items = [
      item("match", "2026-10-02T12:00:00+09:00", "nishi@example.com"),
      item("too_old", "2026-09-30T23:59:59+09:00", "nishi@example.com"),
      item("wrong_user", "2026-10-02T12:00:00+09:00", "other@example.com")
    ]
    scanner = FakeScanner.new(items)
    audit = GoogleDriveAudit::Audit.new(
      scanner: scanner,
      from: "2026-10-01T00:00:00+09:00",
      to: "2026-10-03T00:00:00+09:00",
      user_email: "NISHI@example.com"
    )

    assert_equal ["match"], audit.rows("root").map(&:name)
  end

  def test_rows_can_exclude_folders
    folder = item("folder", "2026-10-02T12:00:00+09:00", "nishi@example.com", mime_type: GoogleDriveAudit::DriveScanner::FOLDER_MIME_TYPE)
    scanner = FakeScanner.new([folder])
    audit = GoogleDriveAudit::Audit.new(
      scanner: scanner,
      from: "2026-10-01T00:00:00+09:00",
      to: "2026-10-03T00:00:00+09:00",
      user_email: "nishi@example.com",
      include_folders: false
    )

    assert_empty audit.rows("root")
  end

  private

  def item(name, modified_time, email, mime_type: "text/plain")
    Item.new(
      id: name,
      name: name,
      mime_type: mime_type,
      modified_time: modified_time,
      created_time: modified_time,
      web_view_link: "https://example.com/#{name}",
      last_modifying_user_email: email,
      last_modifying_user_name: email,
      path: name
    )
  end

  class FakeScanner
    def initialize(items)
      @items = items
    end

    def each_item(_root_id)
      @items.each
    end
  end
end
