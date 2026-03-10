Rails.configuration.to_prepare do
  require_relative "lib/redmine_comment_pdftopng"
end

Redmine::Plugin.register :redmine_comment_pdftopng do
  name "Redmine Comment PDF to PNG"
  author "Leander Kretschmer"
  author_url "https://github.com/leanderkretschmer/"
  version "0.0.1"
  requires_redmine version_or_higher: "6.0.0"

  settings default: {
    "enabled" => "1",
    "scope_mode" => "all",
    "project_ids" => [],
    "issue_ids" => "",
    "render_mode" => "cover",
    "quality" => "medium",
    "tool" => "mini_magick",
    "thumbnail_max_px" => "900"
  }, partial: "settings/redmine_comment_pdftopng_settings"
end
