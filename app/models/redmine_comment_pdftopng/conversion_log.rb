module RedmineCommentPdftopng
  class ConversionLog < ActiveRecord::Base
    self.table_name = "redmine_comment_pdftopng_conversion_logs"

    belongs_to :project, optional: true
    belongs_to :issue, optional: true
    belongs_to :journal, optional: true
    belongs_to :user, optional: true
    belongs_to :pdf_attachment, class_name: "Attachment", optional: true
  end
end
