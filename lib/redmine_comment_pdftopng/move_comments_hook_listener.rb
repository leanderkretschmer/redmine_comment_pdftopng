module RedmineCommentPdftopng
  # Listens for the :move_comments_after_journal_move hook emitted by the
  # redmine_move_comments plugin and re-runs PDF→PNG conversion against
  # the target issue. Needed because the move plugin creates a brand-new
  # Journal and only attaches the attachment JournalDetails *after* the
  # journal save, so the generic after_commit :on => :create hook fires
  # too early to see them.
  class MoveCommentsHookListener < Redmine::Hook::Listener
    def move_comments_after_journal_move(context = {})
      return unless Setting.plugin_redmine_comment_pdftopng

      new_journal = context[:new_journal]
      return unless new_journal.respond_to?(:id) && new_journal.id
      return unless new_journal.respond_to?(:details)
      return unless new_journal.details.to_a.any? { |d| d.property.to_s == "attachment" }

      ConvertJournalJob.perform_later(new_journal.id)
      target_id = context[:target_issue].respond_to?(:id) ? context[:target_issue].id : nil
      Rails.logger.info("[PDF-PNG] enqueued journal=#{new_journal.id} reason=move_comments_after_journal_move target_issue=#{target_id}")
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] move hook failed journal=#{new_journal&.id} #{e.class}: #{e.message}")
    end
  end
end
