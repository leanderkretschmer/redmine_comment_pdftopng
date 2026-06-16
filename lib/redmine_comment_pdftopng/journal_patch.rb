require_dependency "journal"

module RedmineCommentPdftopng
  module JournalPatch
    def self.included(base)
      base.after_commit :pdf_png_enqueue_conversion, on: :create
    end

    private

    def pdf_png_enqueue_conversion
      return unless Setting.plugin_redmine_comment_pdftopng
      return unless respond_to?(:journalized_type) && journalized_type.to_s == "Issue"
      return unless respond_to?(:details) && details.to_a.any? { |d| d.property.to_s == "attachment" }

      RedmineCommentPdftopng::ConvertJournalJob.perform_later(id)
      Rails.logger.info("[PDF-PNG] enqueued journal=#{id}")
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] enqueue failed journal=#{id} #{e.class}: #{e.message}")
    end
  end
end

unless Journal.included_modules.include?(RedmineCommentPdftopng::JournalPatch)
  Journal.send(:include, RedmineCommentPdftopng::JournalPatch)
end
