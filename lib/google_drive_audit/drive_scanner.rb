# frozen_string_literal: true

require "multi_json"
require "multi_json/adapters/yajl"
MultiJSON.use :yajl

require "google/apis/drive_v3"
require "uri"

module GoogleDriveAudit
  class DriveScanner
    FOLDER_MIME_TYPE = "application/vnd.google-apps.folder"
    FILE_FIELDS = [
      "id",
      "name",
      "mimeType",
      "modifiedTime",
      "createdTime",
      "webViewLink",
      "lastModifyingUser(emailAddress,displayName)"
    ].join(",")

    Item = Data.define(
      :id,
      :name,
      :mime_type,
      :modified_time,
      :created_time,
      :web_view_link,
      :last_modifying_user_email,
      :last_modifying_user_name,
      :path
    ) do
      def folder?
        mime_type == FOLDER_MIME_TYPE
      end

      def type
        folder? ? "folder" : "file"
      end
    end

    def initialize(credentials:)
      @service = Google::Apis::DriveV3::DriveService.new
      service.authorization = credentials
    end

    def self.extract_id(value)
      return value unless value.include?("/")

      uri = URI.parse(value)
      segments = uri.path.split("/")
      folders_index = segments.index("folders")
      return segments[folders_index + 1] if folders_index && segments[folders_index + 1]

      file_index = segments.index("d")
      return segments[file_index + 1] if file_index && segments[file_index + 1]

      query = URI.decode_www_form(uri.query || "").to_h
      query["id"] || value
    rescue URI::InvalidURIError
      value
    end

    def each_item(root_id)
      return enum_for(:each_item, root_id) unless block_given?

      root = get_file(root_id)
      root_item = build_item(root, path: root.name)
      yield root_item

      queue = [[root.id, root.name]]
      until queue.empty?
        parent_id, parent_path = queue.shift
        list_children(parent_id).each do |file|
          item = build_item(file, path: "#{parent_path}/#{file.name}")
          yield item
          queue << [file.id, item.path] if item.folder?
        end
      end
    end

    private

    attr_reader :service

    def get_file(file_id)
      service.get_file(
        file_id,
        fields: FILE_FIELDS,
        supports_all_drives: true
      )
    end

    def list_children(parent_id)
      Enumerator.new do |yielder|
        page_token = nil
        loop do
          response = service.list_files(
            q: "'#{escape_query_value(parent_id)}' in parents and trashed = false",
            fields: "nextPageToken, files(#{FILE_FIELDS})",
            page_size: 1000,
            page_token: page_token,
            include_items_from_all_drives: true,
            supports_all_drives: true,
            corpora: "allDrives"
          )
          response.files.each { |file| yielder << file }
          page_token = response.next_page_token
          break unless page_token
        end
      end
    end

    def build_item(file, path:)
      user = file.last_modifying_user
      Item.new(
        id: file.id,
        name: file.name,
        mime_type: file.mime_type,
        modified_time: file.modified_time,
        created_time: file.created_time,
        web_view_link: file.web_view_link,
        last_modifying_user_email: user&.email_address,
        last_modifying_user_name: user&.display_name,
        path: path
      )
    end

    def escape_query_value(value)
      value.gsub("\\", "\\\\\\").gsub("'", "\\\\'")
    end
  end
end
