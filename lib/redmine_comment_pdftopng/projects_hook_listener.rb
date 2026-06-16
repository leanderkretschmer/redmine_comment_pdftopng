module RedmineCommentPdftopng
  class ProjectsHookListener < Redmine::Hook::ViewListener
    def view_projects_form(context = {})
      project = context[:project]
      return "" unless project.respond_to?(:module_enabled?) && project.module_enabled?(:pdftopng)
      return "" unless context[:controller].respond_to?(:render_to_string)

      current = Settings.per_project_conversion_disabled_raw(project.id)
      context[:controller].render_to_string(
        partial: "projects/pdftopng_project_settings",
        locals: { project: project, current: current }
      )
    end

    def controller_projects_edit_after_save(context = {})
      project = context[:project]
      params  = context[:params]
      return unless project && params
      return unless project.respond_to?(:module_enabled?) && project.module_enabled?(:pdftopng)

      key = params.key?(:pdftopng_disabled_issue_ids) ? :pdftopng_disabled_issue_ids : "pdftopng_disabled_issue_ids"
      return unless params.key?(key)

      Settings.store_per_project_conversion_disabled(project.id, params[key])
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] persist per-project disabled list failed project=#{project&.id} #{e.class}: #{e.message}")
    end
  end
end
