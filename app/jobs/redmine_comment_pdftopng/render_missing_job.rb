module RedmineCommentPdftopng
  class RenderMissingJob < ActiveJob::Base
    queue_as :default

    def perform(trigger_user_id = nil)
      trigger_user = trigger_user_id ? User.find_by(id: trigger_user_id) : nil
      journals = eligible_journals
      Rails.logger.info("[PDF-PNG] render_missing start user_id=#{trigger_user_id} journals=#{journals.count}")

      journals.find_each(batch_size: 200) do |journal|
        issue = journal.journalized
        next unless issue.is_a?(Issue)

        pdfs = pdf_attachments_for(journal)
        next if pdfs.empty?

        next unless pdfs.any? { |pdf| missing_for_issue?(issue, pdf) }

        user = journal.user || trigger_user || User.anonymous
        Processor.new(issue: issue, journal: journal, user: user).call
      end

      Rails.logger.info("[PDF-PNG] render_missing done user_id=#{trigger_user_id}")
    end

    private

    def eligible_journals
      scope =
        Journal
          .where(journalized_type: "Issue")
          .joins(:details)
          .where(journal_details: { property: "attachment" })
          .distinct

      return scope if Settings.scope_mode.to_s != "manual"

      project_identifiers = Settings.project_identifiers
      issue_ids = Settings.issue_ids
      return scope if project_identifiers.empty? && issue_ids.empty?

      if project_identifiers.any?
        scope =
          scope
            .joins("INNER JOIN issues ON issues.id = journals.journalized_id")
            .joins("INNER JOIN projects ON projects.id = issues.project_id")
      end

      if project_identifiers.any? && issue_ids.any?
        scope.where("(projects.identifier IN (?) OR journals.journalized_id IN (?))", project_identifiers, issue_ids)
      elsif project_identifiers.any?
        scope.where("projects.identifier IN (?)", project_identifiers)
      else
        scope.where(journalized_id: issue_ids)
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

      !issue.attachments.to_a.any? do |a|
        fn = a.filename.to_s
        fn.start_with?(base_key) && fn.downcase.end_with?(".png")
      end
    rescue StandardError
      true
    end
  end
end
