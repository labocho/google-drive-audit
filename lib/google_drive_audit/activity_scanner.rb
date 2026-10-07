# frozen_string_literal: true

require "multi_json"
require "multi_json/adapters/yajl"
MultiJSON.use :yajl

require "google/apis/driveactivity_v2"
require "time"

module GoogleDriveAudit
  class ActivityScanner
    ActivityRow = Data.define(
      :id,
      :name,
      :mime_type,
      :modified_time,
      :created_time,
      :web_view_link,
      :last_modifying_user_email,
      :last_modifying_user_name,
      :path,
      :action,
      :old_parent_path,
      :new_parent_path,
      :old_parent_url,
      :new_parent_url
    ) do
      def folder?
        false
      end

      def type
        action
      end
    end

    def initialize(credentials:)
      @service = Google::Apis::DriveactivityV2::DriveActivityService.new
      service.authorization = credentials
    end

    def move_rows(root_id, from:, to:, user_email:)
      query(root_id, from: from, to: to).filter_map do |activity|
        next unless current_user_actor?(activity)

        build_row(activity, user_email: user_email)
      end
    end

    private

    attr_reader :service

    def query(root_id, from:, to:)
      Enumerator.new do |yielder|
        page_token = nil
        loop do
          request = Google::Apis::DriveactivityV2::QueryDriveActivityRequest.new(
            ancestor_name: "items/#{root_id}",
            filter: activity_filter(from: from, to: to),
            page_size: 100,
            page_token: page_token
          )
          response = service.query_drive_activity(request)
          Array(response.activities).each { |activity| yielder << activity }
          page_token = response.next_page_token
          break unless page_token
        end
      end
    end

    def activity_filter(from:, to:)
      %(time >= "#{from.iso8601}" time <= "#{to.iso8601}" detail.action_detail_case:MOVE)
    end

    def current_user_actor?(activity)
      Array(activity.actors).any? do |actor|
        actor.user&.known_user&.is_current_user ||
          actor.impersonation&.impersonated_user&.known_user&.is_current_user
      end
    end

    def build_row(activity, user_email:)
      target = Array(activity.targets).find(&:drive_item)&.drive_item
      title = target&.title || "(unknown)"
      id = target&.name&.sub(%r{\Aitems/}, "")
      time = activity.timestamp || activity.time_range&.end_time || activity.time_range&.start_time
      move = activity.primary_action_detail&.move
      ActivityRow.new(
        id: id,
        name: title,
        mime_type: target&.mime_type,
        modified_time: time,
        created_time: nil,
        web_view_link: id ? "https://drive.google.com/open?id=#{id}" : nil,
        last_modifying_user_email: user_email,
        last_modifying_user_name: user_email,
        path: title,
        action: "move",
        old_parent_path: parent_names(move&.removed_parents),
        new_parent_path: parent_names(move&.added_parents),
        old_parent_url: parent_urls(move&.removed_parents),
        new_parent_url: parent_urls(move&.added_parents)
      )
    end

    def parent_names(parent_references)
      Array(parent_references).filter_map { |reference| parent_name(reference) }.join("; ")
    end

    def parent_urls(parent_references)
      Array(parent_references).filter_map { |reference| parent_url(reference) }.join("; ")
    end

    def parent_name(reference)
      drive_item = reference&.drive_item
      return unless drive_item

      drive_item.respond_to?(:title) ? drive_item.title : nil
    end

    def parent_url(reference)
      drive_item = reference&.drive_item
      return unless drive_item

      id = drive_item.name&.sub(%r{\Aitems/}, "")
      id ? "https://drive.google.com/open?id=#{id}" : nil
    end
  end
end
