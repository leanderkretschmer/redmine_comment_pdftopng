module RedmineCommentPdftopng
  class Processor
    LOG_PREFIX = "[PDF-PNG]".freeze

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
      Rails.logger.error("#{LOG_PREFIX} error issue=#{@issue&.id} journal=#{@journal&.id} #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    end

    private

    def eligible_scope?
      return true if Settings.scope_mode.to_s != "manual"

      project_identifiers = Settings.project_identifiers
      issue_ids = Settings.issue_ids
      return true if project_identifiers.empty? && issue_ids.empty?

      issue_ids.include?(@issue.id) || project_identifiers.include?(@issue&.project&.identifier.to_s)
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

      Rails.logger.info("#{LOG_PREFIX} start issue=#{@issue.id} journal=#{@journal.id} pdf_attachment=#{pdf_attachment.id} filename=#{pdf_attachment.filename}")
      Rails.logger.info("#{LOG_PREFIX} settings render_mode=#{Settings.render_mode} thumbnail_max_px=#{Settings.thumbnail_max_px} page_max_px=#{Settings.page_max_px}")
      Rails.logger.info("#{LOG_PREFIX} pdf_path=#{pdf_path}")

      existing_pngs = existing_png_attachments(pdf_attachment)
      if existing_pngs.any?
        update_journal_notes(existing_pngs)
        Rails.logger.info("#{LOG_PREFIX} reuse issue=#{@issue.id} pdf_attachment=#{pdf_attachment.id} pngs=#{existing_pngs.size}")
        return
      end

      render_mode = Settings.render_mode
      max_px = render_mode == "all_pages" ? Settings.page_max_px : Settings.thumbnail_max_px
      quality = render_mode == "all_pages" ? "original" : "medium"
      converter = PdfConverter.new(
        pdf_path: pdf_path,
        render_mode: render_mode,
        quality: quality,
        max_px: max_px
      )

      begin
        result = converter.convert
        begin
          Rails.logger.info("#{LOG_PREFIX} converted pdf_attachment=#{pdf_attachment.id} output_files=#{result.output_files.size}")
          if result.output_files.empty?
            raise "converter produced no files"
          end
          png_attachments = attach_pngs(pdf_attachment, result.output_files)
          update_journal_notes(png_attachments) if png_attachments.any?
          Rails.logger.info("#{LOG_PREFIX} done issue=#{@issue.id} pdf_attachment=#{pdf_attachment.id} pngs=#{png_attachments.size}")
        ensure
          tmp_dir = result.respond_to?(:tmp_dir) ? result.tmp_dir.to_s : ""
          if tmp_dir.present? && File.directory?(tmp_dir)
            require "fileutils"
            FileUtils.remove_entry(tmp_dir)
          end
        end
      rescue StandardError => e
        Rails.logger.error("#{LOG_PREFIX} failed issue=#{@issue.id} pdf_attachment=#{pdf_attachment.id} #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
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
      base_key = base_key_for(pdf_attachment)

      desired_filenames =
        if Settings.render_mode == "all_pages"
          png_paths.each_with_index.map { |_, idx| "#{base_key}_p#{format("%03d", idx + 1)}.png" }
        else
          ["#{base_key}_cover.png"]
        end

      existing = @issue.attachments.to_a.index_by(&:filename)
      page_count = Settings.render_mode == "all_pages" ? png_paths.size : 1
      page_count = 1 if page_count <= 0

      png_paths.zip(desired_filenames).each_with_index do |(png_path, filename), idx|
        next if existing.key?(filename)

        attachment = build_png_attachment(filename, png_path, pdf_attachment, page_index: idx + 1, page_count: page_count)
        next unless attachment

        existing[filename] = attachment
      end

      desired_filenames.filter_map { |fn| existing[fn] }
    end

    def existing_png_attachments(pdf_attachment)
      base_key = base_key_for(pdf_attachment)
      @issue
        .attachments
        .to_a
        .select do |a|
          fn = a.filename.to_s
          fn.start_with?(base_key) && fn.downcase.end_with?(".png")
        end
        .sort_by { |a| a.filename.to_s }
    end

    def build_png_attachment(filename, png_path, pdf_attachment, page_index:, page_count:)
      author = (@journal.respond_to?(:user) ? @journal.user : nil) || @user || User.anonymous
      return nil unless author
      description = png_description_for(pdf_attachment, page_index: page_index, page_count: page_count)

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
            author: author,
            description: description
          )

        attachment.file = uploaded
        return attachment if attachment.save
      end

      nil
    rescue StandardError => e
      Rails.logger.error("#{LOG_PREFIX} attach failed: #{e.class}: #{e.message}")
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

    def base_key_for(pdf_attachment)
      base = File.basename(pdf_attachment.filename.to_s, File.extname(pdf_attachment.filename.to_s))
      safe_base = base.gsub(/[^\w.\- ]+/, "_").strip
      "#{safe_base}_a#{pdf_attachment.id}"
    end

    def png_description_for(pdf_attachment, page_index:, page_count:)
      template = Settings.png_description_template.to_s
      filename = pdf_attachment.filename.to_s
      page_index = page_index.to_i
      page_count = page_count.to_i
      page_index = 1 if page_index <= 0
      page_count = 1 if page_count <= 0

      desc =
        template
          .gsub("{filename}", filename)
          .gsub("{page}", page_index.to_s)
          .gsub("{pages}", page_count.to_s)

      desc % { filename: filename, page: page_index, pages: page_count }
    rescue StandardError
      "Seite #{page_index}/#{page_count} #{filename}"
    end
  end
end
