require "securerandom"
require "tmpdir"
require "fileutils"
require "open3"

module RedmineCommentPdftopng
  class PdfConverter
    LOG_PREFIX = "[PDF-PNG]".freeze
    ConversionResult = Struct.new(:output_files, :tmp_dir, :bytes_before, :bytes_after, :pngquant_used, keyword_init: true)
    MAGICK_LIMIT = "1GiB".freeze

    QUALITY_PRESETS = {
      "low" => { density: 72, compression: 9, max_px: 900 },
      "medium" => { density: 150, compression: 6, max_px: 1600 },
      "high" => { density: 300, compression: 3, max_px: nil },
      "original" => { density: 600, compression: 0, max_px: nil }
    }.freeze

    def initialize(pdf_path:, render_mode:, quality:, max_px:)
      @pdf_path = pdf_path
      @render_mode = render_mode
      @quality = quality
      @max_px = max_px
    end

    def convert
      ensure_backend_loaded!

      tmp_dir = Dir.mktmpdir("redmine_comment_pdftopng_")
      success = false
      Rails.logger.info("#{LOG_PREFIX} convert mode=#{@render_mode} quality=#{@quality} pdf=#{@pdf_path}") if defined?(Rails)

      output_files =
        begin
          if @render_mode == "all_pages"
            convert_all_pages(tmp_dir)
          else
            [convert_cover(tmp_dir)]
          end
        rescue StandardError => e
          if defined?(Rails)
            Rails.logger.error("#{LOG_PREFIX} convert failed #{e.class}: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
            if e.message.to_s =~ /not allowed by the security policy|no decode delegate/i
              Rails.logger.error("#{LOG_PREFIX} ImageMagick PDF support/policy blocks PDF. Enable PDF/ghostscript in ImageMagick policy.xml.")
            end
          end
          raise
        end

      files = Array(output_files).select { |p| p.to_s.present? && File.exist?(p.to_s) }
      bytes_before = total_size(files)
      pngquant_used = maybe_pngquant_compress!(files)
      bytes_after = total_size(files)
      success = true
      ConversionResult.new(
        output_files: files,
        tmp_dir: tmp_dir,
        bytes_before: bytes_before,
        bytes_after: bytes_after,
        pngquant_used: pngquant_used
      )
    ensure
      FileUtils.remove_entry(tmp_dir) if !success && tmp_dir && File.directory?(tmp_dir)
    end

    private

    def ensure_backend_loaded!
      require "mini_magick"
    rescue LoadError => e
      raise "Abhängigkeit fehlt: #{e.message}"
    end

    def maybe_pngquant_compress!(files)
      return if files.empty?
      return unless self.class.pngquant_available?

      cmd = self.class.pngquant_cmd
      files.each do |path|
        next unless File.file?(path)

        tmp_out = File.join(File.dirname(path), "pngquant_#{SecureRandom.hex(8)}.png")
        args = ["--force", "--skip-if-larger", "--strip", "--speed", "1", "--quality", "60-80", "--output", tmp_out, path]

        _stdout, stderr, status = Open3.capture3(cmd, *args)
        if status.success? && File.file?(tmp_out)
          FileUtils.mv(tmp_out, path, force: true)
        else
          FileUtils.rm_f(tmp_out)
          Rails.logger.warn("#{LOG_PREFIX} pngquant failed file=#{path} exit=#{status.exitstatus} err=#{stderr.to_s.strip}") if defined?(Rails)
        end
      rescue StandardError => e
        FileUtils.rm_f(tmp_out) if tmp_out
        Rails.logger.warn("#{LOG_PREFIX} pngquant error file=#{path} #{e.class}: #{e.message}") if defined?(Rails)
      end
      true
    end

    def self.pngquant_cmd
      if defined?(Settings) && Settings.respond_to?(:pngquant_path)
        Settings.pngquant_path.to_s.presence || "pngquant"
      else
        "pngquant"
      end
    end

    def self.pngquant_available?
      cmd = pngquant_cmd
      @pngquant_available_by_cmd ||= {}
      cached = @pngquant_available_by_cmd[cmd]
      return cached unless cached.nil?

      _stdout, _stderr, status = Open3.capture3(cmd, "--version")
      @pngquant_available_by_cmd[cmd] = status.success?
    rescue StandardError
      @pngquant_available_by_cmd ||= {}
      @pngquant_available_by_cmd[cmd] = false
    end

    def self.pngquant_version
      cmd = pngquant_cmd
      stdout, stderr, status = Open3.capture3(cmd, "--version")
      return nil unless status.success?

      v = stdout.to_s.strip
      v = stderr.to_s.strip if v.blank?
      v.presence
    rescue StandardError
      nil
    end

    def total_size(paths)
      Array(paths).sum { |p| File.file?(p) ? File.size(p).to_i : 0 }
    end

    def convert_cover(tmp_dir)
      preset = QUALITY_PRESETS.fetch(@quality, QUALITY_PRESETS.fetch("medium"))
      max_px = @max_px.to_i.positive? ? @max_px.to_i : preset[:max_px]
      out_path = File.join(tmp_dir, "cover_#{SecureRandom.hex(8)}.png")
      density = effective_density(preset[:density], max_px)

      MiniMagick::Tool::Convert.new do |convert|
        apply_resource_limits(convert)
        convert.density(density)
        convert << "#{@pdf_path}[0]"
        apply_png_options(convert, preset: preset, max_px: max_px)
        convert << out_path
      end

      out_path
    end

    def convert_all_pages(tmp_dir)
      convert_all_pages_with_minimagick(tmp_dir)
    end

    def convert_all_pages_with_minimagick(tmp_dir)
      preset = QUALITY_PRESETS.fetch(@quality, QUALITY_PRESETS.fetch("medium"))
      max_px = @max_px.to_i.positive? ? @max_px.to_i : preset[:max_px]
      out_pattern = File.join(tmp_dir, "page_%03d.png")
      density = effective_density(preset[:density], max_px)

      MiniMagick::Tool::Convert.new do |convert|
        apply_resource_limits(convert)
        convert.density(density)
        convert << "-scene" << "1"
        convert << @pdf_path
        apply_png_options(convert, preset: preset, max_px: max_px)
        convert << out_pattern
      end

      Dir.glob(File.join(tmp_dir, "page_*.png")).sort
    end

    def apply_png_options(convert, preset:, max_px:)
      convert << "-colorspace" << "sRGB"
      convert << "-alpha" << "remove"
      convert << "-define" << "png:compression-level=#{preset[:compression]}"
      convert << "-strip"
      convert << "-resize" << "#{max_px}x#{max_px}>" if max_px
    end

    def apply_resource_limits(convert)
      convert << "-limit" << "memory" << MAGICK_LIMIT
      convert << "-limit" << "map" << MAGICK_LIMIT
      convert << "-limit" << "disk" << MAGICK_LIMIT
    end

    def effective_density(preset_density, max_px)
      return preset_density.to_i if max_px.blank? || max_px.to_i <= 0

      dims = pdf_dimensions_at_72dpi
      return preset_density.to_i if dims.nil?

      max_dim = dims.max.to_f
      return preset_density.to_i if max_dim <= 0

      density_cap = (72.0 * (max_px.to_f / max_dim)).floor
      density_cap = 30 if density_cap < 30
      density = [preset_density.to_i, density_cap.to_i].min

      Rails.logger.info("#{LOG_PREFIX} density preset=#{preset_density} cap=#{density_cap} effective=#{density}") if defined?(Rails) && density != preset_density.to_i
      density
    rescue StandardError => e
      Rails.logger.warn("#{LOG_PREFIX} density calc failed #{e.class}: #{e.message}") if defined?(Rails)
      preset_density.to_i
    end

    def pdf_dimensions_at_72dpi
      out =
        MiniMagick::Tool::Identify.new do |identify|
          identify.density(72)
          identify.format("%w %h")
          identify << "#{@pdf_path}[0]"
        end

      w_str, h_str = out.to_s.strip.split(/\s+/, 2)
      w = w_str.to_i
      h = h_str.to_i
      return nil if w <= 0 || h <= 0

      [w, h]
    end
  end
end
