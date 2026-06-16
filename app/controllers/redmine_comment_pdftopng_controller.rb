class RedmineCommentPdftopngController < ApplicationController
  before_action :require_admin

  SCAN_CACHE_KEY = "redmine_comment_pdftopng:last_scan:v1".freeze

  def render_missing
    Rails.logger.info("[PDF-PNG] render_missing requested by user_id=#{User.current.id}")
    RedmineCommentPdftopng::RenderMissingJob.perform_later(User.current.id)
    redirect_to({ controller: "settings", action: "plugin", id: "redmine_comment_pdftopng" }, notice: l(:notice_successful_update))
  end

  def scan_issue
    return redirect_back_to_settings(alert: l(:label_rcpp_dev_tools_disabled)) unless RedmineCommentPdftopng::Settings.dev_tools_enabled?

    issue = Issue.find_by(id: params[:issue_id].to_i)
    return redirect_back_to_settings(alert: l(:text_rcpp_dev_issue_not_found)) unless issue

    pngs = issue_pngs(issue)
    pdfs = issue.attachments.to_a.select { |a| a.filename.to_s.downcase.end_with?(".pdf") }

    write_scan_result(
      issue_id: issue.id,
      issue_subject: issue.subject.to_s,
      pdf_count: pdfs.size,
      png_count: pngs.size,
      pdf_filenames: pdfs.map { |a| a.filename.to_s },
      png_filenames: pngs.map { |a| a.filename.to_s },
      scanned_at: Time.now.utc.iso8601
    )

    Rails.logger.info("[PDF-PNG][DEV] scan issue=#{issue.id} pdfs=#{pdfs.size} pngs=#{pngs.size} user_id=#{User.current.id}")
    redirect_back_to_settings(notice: l(:text_rcpp_dev_scan_done, pdf_count: pdfs.size, png_count: pngs.size, issue: issue.id))
  end

  def purge_issue_pngs
    return redirect_back_to_settings(alert: l(:label_rcpp_dev_tools_disabled)) unless RedmineCommentPdftopng::Settings.dev_tools_enabled?

    issue = Issue.find_by(id: params[:issue_id].to_i)
    return redirect_back_to_settings(alert: l(:text_rcpp_dev_issue_not_found)) unless issue

    pngs = issue_pngs(issue)
    destroyed = 0

    pngs.each do |a|
      JournalDetail.where(property: "attachment", prop_key: a.id.to_s).destroy_all
      destroyed += 1 if a.destroy
    end

    Rails.logger.warn("[PDF-PNG][DEV] purge issue=#{issue.id} destroyed=#{destroyed} user_id=#{User.current.id}")
    write_scan_result(
      issue_id: issue.id,
      issue_subject: issue.subject.to_s,
      pdf_count: issue.attachments.to_a.count { |a| a.filename.to_s.downcase.end_with?(".pdf") },
      png_count: issue_pngs(issue.reload).size,
      pdf_filenames: [],
      png_filenames: [],
      scanned_at: Time.now.utc.iso8601,
      last_purge_destroyed: destroyed
    )
    redirect_back_to_settings(notice: l(:text_rcpp_dev_purge_done, destroyed: destroyed, issue: issue.id))
  end

  private

  def issue_pngs(issue)
    issue
      .attachments
      .to_a
      .select { |a| a.filename.to_s =~ RedmineCommentPdftopng::NoteMarkup::PNG_PATTERN }
      .sort_by { |a| a.filename.to_s }
  end

  def write_scan_result(payload)
    Rails.cache.write(SCAN_CACHE_KEY, payload, expires_in: 30.minutes)
  end

  def redirect_back_to_settings(notice: nil, alert: nil)
    options = { controller: "settings", action: "plugin", id: "redmine_comment_pdftopng" }
    flash_opts = {}
    flash_opts[:notice] = notice if notice
    flash_opts[:alert]  = alert  if alert
    redirect_to(options, **flash_opts)
  end
end
