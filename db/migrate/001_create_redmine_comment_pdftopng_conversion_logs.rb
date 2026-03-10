class CreateRedmineCommentPdftopngConversionLogs < ActiveRecord::Migration[6.1]
  def change
    idx_created_at = "idx_rcpp_conv_logs_created_at"
    idx_issue_id = "idx_rcpp_conv_logs_issue_id"
    idx_pdf_attachment_id = "idx_rcpp_conv_logs_pdf_attachment_id"

    if table_exists?(:redmine_comment_pdftopng_conversion_logs)
      add_index :redmine_comment_pdftopng_conversion_logs, :created_at, name: idx_created_at unless index_exists?(:redmine_comment_pdftopng_conversion_logs, :created_at, name: idx_created_at)
      add_index :redmine_comment_pdftopng_conversion_logs, :issue_id, name: idx_issue_id unless index_exists?(:redmine_comment_pdftopng_conversion_logs, :issue_id, name: idx_issue_id)
      add_index :redmine_comment_pdftopng_conversion_logs, :pdf_attachment_id, name: idx_pdf_attachment_id unless index_exists?(:redmine_comment_pdftopng_conversion_logs, :pdf_attachment_id, name: idx_pdf_attachment_id)
      return
    end

    create_table :redmine_comment_pdftopng_conversion_logs do |t|
      t.integer :project_id
      t.integer :issue_id
      t.integer :journal_id
      t.integer :user_id
      t.integer :pdf_attachment_id
      t.string :pdf_filename
      t.string :render_mode
      t.string :quality
      t.string :tool
      t.text :png_filenames
      t.string :status, null: false, default: "ok"
      t.text :error_text
      t.datetime :created_at, null: false
    end

    add_index :redmine_comment_pdftopng_conversion_logs, :created_at, name: idx_created_at
    add_index :redmine_comment_pdftopng_conversion_logs, :issue_id, name: idx_issue_id
    add_index :redmine_comment_pdftopng_conversion_logs, :pdf_attachment_id, name: idx_pdf_attachment_id
  end
end
