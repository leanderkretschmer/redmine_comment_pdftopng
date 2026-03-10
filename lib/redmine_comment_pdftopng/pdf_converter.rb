require "securerandom"
require "tmpdir"

module RedmineCommentPdftopng
  class PdfConverter
    ConversionResult = Struct.new(:output_files, keyword_init: true)

    QUALITY_PRESETS = {
      "low" => { density: 72, compression: 9, max_px: 900 },
      "medium" => { density: 150, compression: 6, max_px: 1600 },
      "high" => { density: 300, compression: 3, max_px: nil },
      "original" => { density: 600, compression: 0, max_px: nil }
    }.freeze

    def initialize(pdf_path:, render_mode:, quality:, thumbnail_max_px:, tool:)
      @pdf_path = pdf_path
      @render_mode = render_mode
      @quality = quality
      @thumbnail_max_px = thumbnail_max_px
      @tool = tool
    end

    def convert
      ensure_backend_loaded!

      tmp_dir = Dir.mktmpdir("redmine_comment_pdftopng_")
      output_files =
        if @render_mode == "all_pages"
          convert_all_pages(tmp_dir)
        else
          [convert_cover(tmp_dir)]
        end

      ConversionResult.new(output_files: output_files)
    end

    private

    def ensure_backend_loaded!
      require "mini_magick"
      require "hexapdf" if @tool.to_s == "hexa_pdf"
    rescue LoadError => e
      raise "Abhängigkeit fehlt: #{e.message}"
    end

    def convert_cover(tmp_dir)
      preset = QUALITY_PRESETS.fetch(@quality, QUALITY_PRESETS.fetch("medium"))
      max_px = @thumbnail_max_px.positive? ? @thumbnail_max_px : preset[:max_px]
      out_path = File.join(tmp_dir, "cover_#{SecureRandom.hex(8)}.png")

      MiniMagick::Tool::Convert.new do |convert|
        convert.density(preset[:density])
        convert << "#{@pdf_path}[0]"
        apply_png_options(convert, preset: preset, max_px: max_px)
        convert << out_path
      end

      out_path
    end

    def convert_all_pages(tmp_dir)
      if @tool.to_s == "hexa_pdf"
        convert_all_pages_with_hexapdf(tmp_dir)
      else
        convert_all_pages_with_minimagick(tmp_dir)
      end
    end

    def convert_all_pages_with_minimagick(tmp_dir)
      preset = QUALITY_PRESETS.fetch(@quality, QUALITY_PRESETS.fetch("medium"))
      max_px = preset[:max_px]
      out_pattern = File.join(tmp_dir, "page_%03d.png")

      MiniMagick::Tool::Convert.new do |convert|
        convert.density(preset[:density])
        convert << "-scene" << "1"
        convert << @pdf_path
        apply_png_options(convert, preset: preset, max_px: max_px)
        convert << out_pattern
      end

      Dir.glob(File.join(tmp_dir, "page_*.png")).sort
    end

    def convert_all_pages_with_hexapdf(tmp_dir)
      preset = QUALITY_PRESETS.fetch(@quality, QUALITY_PRESETS.fetch("medium"))
      max_px = preset[:max_px]
      pages = hexa_pdf_page_count
      return [] if pages <= 0

      (0...pages).map do |page_index|
        out_path = File.join(tmp_dir, format("page_%03d.png", page_index + 1))

        MiniMagick::Tool::Convert.new do |convert|
          convert.density(preset[:density])
          convert << "#{@pdf_path}[#{page_index}]"
          apply_png_options(convert, preset: preset, max_px: max_px)
          convert << out_path
        end

        out_path
      end
    end

    def hexa_pdf_page_count
      doc = HexaPDF::Document.open(@pdf_path)
      doc.pages.count
    ensure
      doc&.close if doc.respond_to?(:close)
    end

    def apply_png_options(convert, preset:, max_px:)
      convert << "-colorspace" << "sRGB"
      convert << "-alpha" << "remove"
      convert << "-define" << "png:compression-level=#{preset[:compression]}"
      convert << "-strip"
      convert << "-resize" << "#{max_px}x#{max_px}>" if max_px
    end
  end
end
