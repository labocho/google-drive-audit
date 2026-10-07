# frozen_string_literal: true

require "csv"
require "json"

module GoogleDriveAudit
  module Formatters
    HEADERS = [
      "type",
      "path",
      "name",
      "id",
      "modified_time",
      "created_time",
      "last_modifying_user_email",
      "last_modifying_user_name",
      "old_parent_path",
      "new_parent_path",
      "old_parent_url",
      "new_parent_url",
      "web_view_link"
    ].freeze

    module_function

    def write(rows, format:, io: $stdout)
      case format
      when "csv"
        io.write(to_csv(rows))
      when "json"
        io.write(JSON.pretty_generate(rows.map { |row| serialize(row) }))
        io.write("\n")
      else
        write_table(rows, io: io)
      end
    end

    def to_csv(rows)
      CSV.generate(headers: true) do |csv|
        csv << HEADERS
        rows.each { |row| csv << HEADERS.map { |header| serialize(row).fetch(header) } }
      end
    end

    def write_table(rows, io:)
      records = rows.map { |row| serialize(row) }
      widths = HEADERS.to_h { |header| [header, header.length] }
      records.each do |record|
        HEADERS.each { |header| widths[header] = [widths[header], record[header].to_s.length].max }
      end

      io.puts HEADERS.map { |header| header.ljust(widths[header]) }.join("  ")
      io.puts HEADERS.map { |header| "-" * widths[header] }.join("  ")
      records.each do |record|
        io.puts HEADERS.map { |header| record[header].to_s.ljust(widths[header]) }.join("  ")
      end
    end

    def serialize(row)
      {
        "type" => row.type,
        "path" => row.path,
        "name" => row.name,
        "id" => row.id,
        "modified_time" => row.modified_time,
        "created_time" => row.created_time,
        "last_modifying_user_email" => row.last_modifying_user_email,
        "last_modifying_user_name" => row.last_modifying_user_name,
        "old_parent_path" => optional_value(row, :old_parent_path),
        "new_parent_path" => optional_value(row, :new_parent_path),
        "old_parent_url" => optional_value(row, :old_parent_url),
        "new_parent_url" => optional_value(row, :new_parent_url),
        "web_view_link" => row.web_view_link
      }
    end

    def optional_value(row, method_name)
      row.respond_to?(method_name) ? row.public_send(method_name) : nil
    end
  end
end
