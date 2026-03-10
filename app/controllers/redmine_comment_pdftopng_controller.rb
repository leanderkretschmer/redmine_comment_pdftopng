class RedmineCommentPdftopngController < ApplicationController
  before_action :require_admin

  def render_missing
    Rails.logger.info("[redmine_comment_pdftopng] render_missing requested by user_id=#{User.current.id}")
    RedmineCommentPdftopng::RenderMissingJob.perform_later(User.current.id)
    redirect_to({ controller: "settings", action: "plugin", id: "redmine_comment_pdftopng" }, notice: l(:notice_successful_update))
  end
end
