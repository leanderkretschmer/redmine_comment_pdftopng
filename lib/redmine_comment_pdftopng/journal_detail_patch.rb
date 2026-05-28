require_dependency "journal_detail"

module RedmineCommentPdftopng
  module JournalDetailPatch
    def self.included(base)
      base.after_commit :pdf_png_sync_preview, on: :create
    end

    private

    def pdf_png_sync_preview
      return unless property.to_s == "attachment"
      return unless Setting.plugin_redmine_comment_pdftopng

      attachment = Attachment.find_by(id: prop_key.to_i)
      return unless attachment
      return unless attachment.filename.to_s =~ RedmineCommentPdftopng::NoteMarkup::PNG_PATTERN

      RedmineCommentPdftopng::NoteMarkup.sync(journal)
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] sync preview failed detail=#{id} #{e.class}: #{e.message}")
    end
  end
end

unless JournalDetail.included_modules.include?(RedmineCommentPdftopng::JournalDetailPatch)
  JournalDetail.send(:include, RedmineCommentPdftopng::JournalDetailPatch)
end
