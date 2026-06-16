Rails.configuration.to_prepare do
  require_relative "lib/redmine_comment_pdftopng"
end

Redmine::Plugin.register :redmine_comment_pdftopng do
  name "Redmine Comment PDF to PNG"
  author "Leander Kretschmer"
  description "Converts PDF attachments in Redmine comments to PNG images."
  version "1.0.8"
  url 'https://github.com/leanderkretschmer/redmine_comment_pdftopng'
  author_url "https://github.com/leanderkretschmer/"

  requires_redmine version_or_higher: "6.0.0"

  project_module :pdftopng do
    permission :manage_pdftopng_project_settings, {}, require: :member
  end

  settings default: {
    "enabled" => "1",
    "scope_mode" => "global",
    "project_identifiers" => "",
    "issue_ids" => "",
    "preview_hidden_issue_ids" => "",
    "conversion_disabled_issue_ids" => "",
    "per_project_conversion_disabled" => {},
    "dev_tools_enabled" => "0",
    "render_mode" => "cover",
    "thumbnail_max_px" => "900",
    "page_max_px" => "2500",
    "png_description_template" => "Seite %{page}/%{pages} %{filename}",
    "pngquant_path" => "pngquant"
  }, partial: "settings/redmine_comment_pdftopng_settings"
end
