RedmineApp::Application.routes.draw do
  post "redmine_comment_pdftopng/render_missing", to: "redmine_comment_pdftopng#render_missing"
end
