Rails.configuration.to_prepare do
  require_relative "lib/redmine_comment_pdftopng"
end

Redmine::Plugin.register :redmine_comment_pdftopng do
  name "Redmine Comment PDF to PNG"
  author "Leander Kretschmer"
  description "Converts PDF attachments in Redmine comments to PNG images."
  version "0.0.3"
  url 'https://github.com/leanderkretschmer/redmine_comment_pdftopng'
  author_url "https://github.com/leanderkretschmer/"
  
  requires_redmine version_or_higher: "6.0.0"

  settings default: {
    "enabled" => "1",
    "project_ids" => "",
    "issue_ids" => "",
    "render_mode" => "cover",
    "quality" => "medium",
    "tool" => "mini_magick",
    "thumbnail_max_px" => "900",
    "author_mode" => "comment",
    "fixed_user_id" => ""
  }, partial: "settings/redmine_comment_pdftopng_settings"
end
