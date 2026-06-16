module RedmineCommentPdftopng
  # Listens for the :move_comments_after_journal_move hook emitted by the
  # redmine_move_comments plugin and re-runs PDF→PNG conversion against
  # the target issue. Needed because the move plugin creates a brand-new
  # Journal and only attaches the attachment JournalDetails *after* the
  # journal save, so the generic after_commit :on => :create hook fires
  # too early to see them.
  class MoveCommentsHookListener < Redmine::Hook::Listener
    def move_comments_after_journal_move(context = {})
      new_journal = context[:new_journal]
      target_issue = context[:target_issue]
      Rails.logger.info("[PDF-PNG] move hook fired journal=#{new_journal&.id} target_issue=#{target_issue&.id} keys=#{context.keys.inspect}")

      unless Setting.plugin_redmine_comment_pdftopng
        Rails.logger.info("[PDF-PNG] move hook bail: plugin setting nil")
        return
      end

      unless new_journal.respond_to?(:id) && new_journal.id
        Rails.logger.info("[PDF-PNG] move hook bail: no new_journal id")
        return
      end

      # Reload via DB to avoid stale association cache after JournalDetail.create!
      fresh = Journal.find_by(id: new_journal.id)
      unless fresh
        Rails.logger.info("[PDF-PNG] move hook bail: journal lookup failed id=#{new_journal.id}")
        return
      end

      attachment_detail_count = fresh.details.where(property: "attachment").count
      Rails.logger.info("[PDF-PNG] move hook journal=#{fresh.id} attachment_details=#{attachment_detail_count}")

      if attachment_detail_count.zero?
        Rails.logger.info("[PDF-PNG] move hook bail: no attachment details on journal=#{fresh.id}")
        return
      end

      ConvertJournalJob.perform_later(fresh.id)
      Rails.logger.info("[PDF-PNG] enqueued journal=#{fresh.id} reason=move_comments_after_journal_move target_issue=#{target_issue&.id}")
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] move hook failed journal=#{context[:new_journal]&.id} #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(8).join("\n")) if e.backtrace
    end
  end
end
