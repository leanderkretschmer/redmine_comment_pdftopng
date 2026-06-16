RedmineApp::Application.routes.draw do
  post "redmine_comment_pdftopng/render_missing", to: "redmine_comment_pdftopng#render_missing"
  post "redmine_comment_pdftopng/scan_issue", to: "redmine_comment_pdftopng#scan_issue"
  post "redmine_comment_pdftopng/purge_issue_pngs", to: "redmine_comment_pdftopng#purge_issue_pngs"
end
