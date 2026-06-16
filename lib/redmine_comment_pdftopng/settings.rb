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

    def preview_hidden_issue_ids
      raw["preview_hidden_issue_ids"].to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def preview_hidden_for?(issue_id)
      preview_hidden_issue_ids.include?(issue_id.to_i)
    end

    def conversion_disabled_issue_ids
      raw["conversion_disabled_issue_ids"].to_s.split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def conversion_disabled_for?(issue_id)
      conversion_disabled_issue_ids.include?(issue_id.to_i)
    end

    def per_project_conversion_disabled_map
      value = raw["per_project_conversion_disabled"]
      value.is_a?(Hash) ? value : {}
    end

    def per_project_conversion_disabled_raw(project_id)
      per_project_conversion_disabled_map[project_id.to_s].to_s
    end

    def per_project_conversion_disabled_ids(project_id)
      per_project_conversion_disabled_raw(project_id).split(/[\s,;]+/).map(&:to_i).reject(&:zero?)
    end

    def store_per_project_conversion_disabled(project_id, raw_value)
      all = per_project_conversion_disabled_map.dup
      key = project_id.to_s
      cleaned = raw_value.to_s.strip
      if cleaned.empty?
        all.delete(key)
      else
        all[key] = cleaned
      end
      setting = (Setting.plugin_redmine_comment_pdftopng || {}).dup
      setting["per_project_conversion_disabled"] = all
      Setting.plugin_redmine_comment_pdftopng = setting
    end

    def conversion_disabled_for_issue?(issue)
      return false unless issue
      return true if conversion_disabled_issue_ids.include?(issue.id.to_i)
      return false unless issue.respond_to?(:project) && issue.project
      return false unless issue.project.respond_to?(:module_enabled?) && issue.project.module_enabled?(:pdftopng)
      per_project_conversion_disabled_ids(issue.project.id).include?(issue.id.to_i)
    end

    def dev_tools_enabled?
      raw["dev_tools_enabled"].to_s == "1"
    end

    def render_mode
      raw["render_mode"].presence || "cover"
    end

    def thumbnail_max_px
      raw["thumbnail_max_px"].to_i
    end

    def page_max_px
      value = raw["page_max_px"].to_i
      return value if value.positive?

      2500
    end

    def png_description_template
      template = raw["png_description_template"].to_s
      template = "" if template == "{filename} Seite {page}/{pages}"
      template = "" if template == "generated from %{filename}"
      template = "" if template == "generated from {filename}"

      template.presence || "Seite {page}/{pages} {filename}"
    end

    def pngquant_path
      raw["pngquant_path"].presence || "pngquant"
    end

    def parse_identifier_list(value)
      value.to_s.split(/[\s,;]+/).map { |s| s.to_s.strip }.reject(&:blank?)
    end
  end
end
