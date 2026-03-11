module RedmineCommentPdftopng
  module Settings
    module_function

    def raw
      Setting.plugin_redmine_comment_pdftopng || {}
    end

    def enabled?
      raw["enabled"].to_s == "1"
    end

    def scope_mode
      raw["scope_mode"].presence || "global"
    end

    def project_identifiers
      return [] unless scope_mode.to_s == "manual"

      value = raw["project_identifiers"]
      return parse_identifier_list(value) if value.present?

      legacy = raw["project_ids"]
      return [] if legacy.blank?

      ids =
        if legacy.is_a?(Array)
          legacy.map(&:to_i).reject(&:zero?)
        else
          legacy.to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
        end

      return [] if ids.empty?

      Project.where(id: ids).pluck(:identifier).map(&:to_s)
    end

    def issue_ids
      return [] unless scope_mode.to_s == "manual"

      raw["issue_ids"].to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def render_mode
      raw["render_mode"].presence || "cover"
    end

    def quality
      raw["quality"].presence || "medium"
    end

    def thumbnail_max_px
      raw["thumbnail_max_px"].to_i
    end

    def parse_identifier_list(value)
      value.to_s.split(/[\s,;]+/).map { |s| s.to_s.strip }.reject(&:blank?)
    end
  end
end
