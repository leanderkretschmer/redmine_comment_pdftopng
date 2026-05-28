module RedmineCommentPdftopng
  module NoteMarkup
    PNG_PATTERN = /_a\d+_(?:cover|p\d+)\.png\z/i.freeze

    module_function

    def markup_for(filename)
      escaped = filename.to_s.gsub(" ", "%20")
      "!#{escaped}!"
    end

    def png_attachments_for(journal)
      ids =
        JournalDetail
          .where(journal_id: journal.id, property: "attachment")
          .pluck(:prop_key)
          .map(&:to_i)
          .reject(&:zero?)

      return [] if ids.empty?

      Attachment
        .where(id: ids)
        .to_a
        .select { |a| a.filename.to_s =~ PNG_PATTERN }
    end

    # Recomputes the inline preview markup of a journal so it matches the
    # hidden-state of the issue the comment currently lives on. Adds the
    # markup when the issue is not hidden, strips it when it is. Idempotent.
    def sync(journal)
      return unless journal && journal.journalized_type.to_s == "Issue"

      pngs = png_attachments_for(journal)
      return if pngs.empty?

      hidden = Settings.preview_hidden_for?(journal.journalized_id)
      notes = journal.notes.to_s
      markups = pngs.map { |a| markup_for(a.filename) }

      new_notes =
        if hidden
          strip_markups(notes, markups)
        else
          add_markups(notes, markups)
        end

      return if new_notes == notes

      journal.update_columns(notes: new_notes)
    rescue StandardError => e
      Rails.logger.error("[PDF-PNG] note markup sync failed journal=#{journal&.id} #{e.class}: #{e.message}") if defined?(Rails)
    end

    def add_markups(notes, markups)
      missing = markups.reject { |m| notes.include?(m) }
      return notes if missing.empty?

      base = notes.to_s
      if base.strip.empty?
        missing.join("\n")
      else
        base + "\n\n" + missing.join("\n")
      end
    end

    def strip_markups(notes, markups)
      result = notes.to_s
      markups.each { |m| result = result.gsub(m, "") }
      result = result.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n")
      result.strip
    end
  end
end
