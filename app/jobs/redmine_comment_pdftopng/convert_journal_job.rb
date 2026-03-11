module RedmineCommentPdftopng
  class ConvertJournalJob < ActiveJob::Base
    queue_as :default

    def perform(journal_id)
      journal = Journal.find_by(id: journal_id)
      return unless journal

      issue = journal.journalized
      return unless issue.is_a?(Issue)

      user = journal.user || User.anonymous
      Processor.new(issue: issue, journal: journal, user: user).call
    end
  end
end
