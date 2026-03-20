require_relative "redmine_comment_pdftopng/settings"
require_relative "redmine_comment_pdftopng/pdf_converter"
require_relative "redmine_comment_pdftopng/processor"
require_relative "redmine_comment_pdftopng/journal_patch"
require "time"

module RedmineCommentPdftopng
  module ConversionLog
    KEY = "redmine_comment_pdftopng:conversion_log:v1".freeze
    MAX_ENTRIES = 200

    module_function

    def append(message)
      entry = { at: Time.now.utc.iso8601, message: message.to_s }
      list = read_all
      list << entry
      write_all(list.last(MAX_ENTRIES))
      entry
    rescue StandardError
      nil
    end

    def entries(limit: 50)
      read_all.last(limit.to_i).reverse
    rescue StandardError
      []
    end

    def format_bytes(bytes)
      b = bytes.to_i
      return "0 B" if b <= 0

      units = ["B", "KB", "MB", "GB"].freeze
      f = b.to_f
      unit_index = 0
      while f >= 1024.0 && unit_index < units.length - 1
        f /= 1024.0
        unit_index += 1
      end

      rounded =
        if f >= 100
          f.round(0).to_i.to_s
        elsif f >= 10
          f.round(1).to_s
        else
          f.round(2).to_s
        end

      "#{rounded} #{units[unit_index]}"
    end

    def read_all
      if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        Rails.cache.read(KEY) || []
      else
        @memory_entries ||= []
      end
    end

    def write_all(list)
      if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        Rails.cache.write(KEY, list)
      else
        @memory_entries = list
      end
    end
    private_class_method :read_all, :write_all
  end
end
