module RedmineCommentPdftopng
  class Processor
    def initialize(issue:, journal:, user:)
      @issue = issue
      @journal = journal
      @user = user
    end

    def call
      return unless Settings.enabled?
      return unless eligible_scope?

      pdf_attachments.each do |pdf|
        convert_pdf_attachment(pdf)
      end
    rescue StandardError => e
      Rails.logger.error("[redmine_comment_pdftopng] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    end

    private

    def eligible_scope?
      case Settings.scope_mode
      when "projects"
        Settings.project_ids.include?(@issue.project_id)
      when "issues"
        Settings.issue_ids.include?(@issue.id)
      else
        true
      end
    end

    def pdf_attachments
      attachments = []

      if @journal.respond_to?(:attachments)
        attachments.concat(Array(@journal.attachments))
      end

      if @journal.respond_to?(:details)
        added_ids =
          @journal.details
            .select { |d| d.property.to_s == "attachment" }
            .map { |d| d.prop_key.to_i }
            .reject(&:zero?)

        attachments.concat(Attachment.where(id: added_ids).to_a) if added_ids.any?
      end

      attachments
        .compact
        .uniq(&:id)
        .select { |a| a.filename.to_s.downcase.end_with?(".pdf") }
    end

    def convert_pdf_attachment(pdf_attachment)
      pdf_path = attachment_path(pdf_attachment)
      return unless pdf_path

      Rails.logger.info("[redmine_comment_pdftopng] issue=#{@issue.id} journal=#{@journal.id} pdf_attachment=#{pdf_attachment.id} filename=#{pdf_attachment.filename}")

      converter = PdfConverter.new(
        pdf_path: pdf_path,
        render_mode: Settings.render_mode,
        quality: Settings.quality,
        thumbnail_max_px: Settings.thumbnail_max_px,
        tool: Settings.tool
      )

      begin
        result = converter.convert
        png_attachments = attach_pngs(pdf_attachment, result.output_files)
        update_journal_notes(png_attachments) if png_attachments.any?
        write_conversion_log(pdf_attachment, png_attachments, status: "ok", error_text: nil)
        Rails.logger.info("[redmine_comment_pdftopng] done issue=#{@issue.id} pdf_attachment=#{pdf_attachment.id} pngs=#{png_attachments.size}")
      rescue StandardError => e
        write_conversion_log(pdf_attachment, [], status: "error", error_text: "#{e.class}: #{e.message}")
        Rails.logger.error("[redmine_comment_pdftopng] failed issue=#{@issue.id} pdf_attachment=#{pdf_attachment.id} #{e.class}: #{e.message}")
        raise
      end
    end

    def attachment_path(attachment)
      path = attachment.respond_to?(:diskfile) ? attachment.diskfile.to_s : ""
      return if path.blank?
      return if !File.exist?(path) || File.directory?(path)

      path
    end

    def attach_pngs(pdf_attachment, png_paths)
      base = File.basename(pdf_attachment.filename.to_s, File.extname(pdf_attachment.filename.to_s))
      safe_base = base.gsub(/[^\w.\- ]+/, "_").strip
      base_key = "#{safe_base}_a#{pdf_attachment.id}"

      desired_filenames =
        if Settings.render_mode == "all_pages"
          png_paths.each_with_index.map { |_, idx| "#{base_key}_p#{format("%03d", idx + 1)}.png" }
        else
          ["#{base_key}_cover.png"]
        end

      existing = @issue.attachments.to_a.index_by(&:filename)
      created = []

      png_paths.zip(desired_filenames).each do |png_path, filename|
        next if existing.key?(filename)

        attachment = build_png_attachment(filename, png_path, pdf_attachment)
        next unless attachment

        created << attachment
        existing[filename] = attachment
      end

      desired_filenames.filter_map { |fn| existing[fn] }
    end

    def build_png_attachment(filename, png_path, pdf_attachment)
      File.open(png_path, "rb") do |io|
        uploaded =
          ActionDispatch::Http::UploadedFile.new(
            tempfile: io,
            filename: filename,
            type: "image/png"
          )

        attachment =
          Attachment.new(
            container: @issue,
            author: @user,
            description: "generated from #{pdf_attachment.filename}"
          )

        attachment.file = uploaded
        return attachment if attachment.save
      end

      nil
    rescue StandardError => e
      Rails.logger.error("[redmine_comment_pdftopng] attach failed: #{e.class}: #{e.message}")
      nil
    end

    def update_journal_notes(png_attachments)
      escaped_markups =
        png_attachments.map do |a|
          escaped = a.filename.to_s.gsub(" ", "%20")
          "!#{escaped}!"
        end

      notes = @journal.notes.to_s
      additions = escaped_markups.reject { |m| notes.include?(m) }
      return if additions.empty?

      @journal.notes = notes + "\n\n" + additions.join("\n")
      @journal.save
    end

    def write_conversion_log(pdf_attachment, png_attachments, status:, error_text:)
      return unless defined?(RedmineCommentPdftopng::ConversionLog)

      RedmineCommentPdftopng::ConversionLog.create!(
        project_id: @issue.project_id,
        issue_id: @issue.id,
        journal_id: @journal.id,
        user_id: @user&.id,
        pdf_attachment_id: pdf_attachment.id,
        pdf_filename: pdf_attachment.filename.to_s,
        render_mode: Settings.render_mode,
        quality: Settings.quality,
        tool: Settings.tool,
        png_filenames: png_attachments.map { |a| a.filename.to_s }.join("\n"),
        status: status,
        error_text: error_text,
        created_at: Time.current
      )
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
      Rails.logger.warn("[redmine_comment_pdftopng] log skipped: #{e.class}: #{e.message}")
    rescue StandardError => e
      Rails.logger.warn("[redmine_comment_pdftopng] log failed: #{e.class}: #{e.message}")
    end
  end
end
