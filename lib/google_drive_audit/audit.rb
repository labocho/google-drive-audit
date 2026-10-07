# frozen_string_literal: true

require "time"

module GoogleDriveAudit
  class Audit
    def initialize(scanner:, from:, to:, user_email:, include_folders: true, activity_scanner: nil)
      @scanner = scanner
      @activity_scanner = activity_scanner
      @from = Time.iso8601(from)
      @to = Time.iso8601(to)
      @user_email = user_email.downcase
      @include_folders = include_folders
    rescue ArgumentError => e
      raise ArgumentError, "日時はISO 8601形式で指定してください: #{e.message}"
    end

    def rows(root_id)
      metadata_rows = scanner.each_item(root_id).filter_map do |item|
        warn "Scanning item: #{item.name} (#{item.id})" if ENV["GDRIVE_AUDIT_DEBUG"]
        next if item.folder? && !include_folders
        next unless modified_in_range?(item.modified_time)
        next unless same_user?(item.last_modifying_user_email)

        item
      end
      activity_rows = activity_scanner ? activity_scanner.move_rows(root_id, from: from, to: to, user_email: user_email) : []
      (metadata_rows + activity_rows).sort_by { |row| row.modified_time.to_s }
    end

    private

    attr_reader :scanner, :activity_scanner, :from, :to, :user_email, :include_folders

    def modified_in_range?(modified_time)
      return false if modified_time.nil?

      time = modified_time.respond_to?(:to_time) ? modified_time.to_time : Time.iso8601(modified_time)
      time >= from && time <= to
    rescue ArgumentError
      false
    end

    def same_user?(email)
      email&.downcase == user_email
    end
  end
end
