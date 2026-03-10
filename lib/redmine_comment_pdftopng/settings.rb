module RedmineCommentPdftopng
  module Settings
    module_function

    def raw
      Setting.plugin_redmine_comment_pdftopng || {}
    end

    def enabled?
      raw["enabled"].to_s == "1"
    end

    def project_ids
      value = raw["project_ids"]
      return value.map(&:to_i).reject(&:zero?) if value.is_a?(Array)

      value.to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def issue_ids
      raw["issue_ids"].to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def render_mode
      raw["render_mode"].presence || "cover"
    end

    def quality
      raw["quality"].presence || "medium"
    end

    def tool
      raw["tool"].presence || "mini_magick"
    end

    def thumbnail_max_px
      raw["thumbnail_max_px"].to_i
    end

    def author_mode
      raw["author_mode"].presence || "comment"
    end

    def fixed_user_id
      raw["fixed_user_id"].to_i
    end
  end
end
