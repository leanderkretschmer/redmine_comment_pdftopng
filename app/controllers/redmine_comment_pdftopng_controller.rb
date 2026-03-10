class RedmineCommentPdftopngController < ApplicationController
  before_action :require_admin

  def render_missing
    RedmineCommentPdftopng::RenderMissingJob.perform_later(User.current.id)
    redirect_to({ controller: "settings", action: "plugin", id: "redmine_comment_pdftopng" }, notice: l(:notice_successful_update))
  end
end
