module RedmineCommentPdftopng
  class RenderMissingJob < ActiveJob::Base
    queue_as :default

    def perform(trigger_user_id = nil)
      trigger_user = trigger_user_id ? User.find_by(id: trigger_user_id) : nil
      journals = eligible_journals

      journals.find_each(batch_size: 200) do |journal|
        issue = journal.journalized
        next unless issue.is_a?(Issue)

        pdfs = pdf_attachments_for(journal)
        next if pdfs.empty?

        next unless pdfs.any? { |pdf| missing_for_issue?(issue, pdf) }

        Processor.new(issue: issue, journal: journal, user: (trigger_user || User.anonymous)).call
      end
    end

    private

    def eligible_journals
      scope =
        Journal
          .where(journalized_type: "Issue")
          .joins(:details)
          .where(journal_details: { property: "attachment" })
          .distinct

      case Settings.scope_mode
      when "projects"
        ids = Settings.project_ids
        return scope.none if ids.empty?
        scope = scope.joins("INNER JOIN issues ON issues.id = journals.journalized_id")
        scope.where("issues.project_id IN (?)", ids)
      when "issues"
        ids = Settings.issue_ids
        return scope.none if ids.empty?
        scope.where(journalized_id: ids)
      else
        scope
      end
    end

    def pdf_attachments_for(journal)
      added_ids =
        journal.details
          .select { |d| d.property.to_s == "attachment" }
          .map { |d| d.prop_key.to_i }
          .reject(&:zero?)

      return [] if added_ids.empty?

      Attachment
        .where(id: added_ids)
        .to_a
        .select { |a| a.filename.to_s.downcase.end_with?(".pdf") }
    end

    def missing_for_issue?(issue, pdf_attachment)
      base = File.basename(pdf_attachment.filename.to_s, File.extname(pdf_attachment.filename.to_s))
      safe_base = base.gsub(/[^\w.\- ]+/, "_").strip
      base_key = "#{safe_base}_a#{pdf_attachment.id}"

      png_exists =
        issue.attachments.to_a.any? do |a|
          fn = a.filename.to_s
          fn.start_with?(base_key) && fn.downcase.end_with?(".png")
        end

      ok_log_exists =
        RedmineCommentPdftopng::ConversionLog
          .where(pdf_attachment_id: pdf_attachment.id, status: "ok")
          .exists?

      !(png_exists && ok_log_exists)
    rescue StandardError
      true
    end
  end
end
