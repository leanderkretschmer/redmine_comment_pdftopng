require_relative "settings"
require_relative "pdf_converter"
require_relative "processor"

module RedmineCommentPdftopng
  class Hooks < Redmine::Hook::Listener
    def controller_issues_edit_after_save(context = {})
      run_for_context(context)
    end

    def controller_issues_new_after_save(context = {})
      run_for_context(context)
    end

    private

    def run_for_context(context)
      issue = context[:issue]
      journal = context[:journal]
      user = context[:user] || User.current

      return unless issue && journal

      Processor.new(issue: issue, journal: journal, user: user).call
    end
  end
end
