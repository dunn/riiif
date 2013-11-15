require 'mini_magick'
module Riiif
  class Image
    class_attribute :file_resolver
    self.file_resolver = FileSystemFileResolver

    OUTPUT_FORMATS = %W{jpg png}

    attr_reader :path_name

    # @param [String] id The identifier of the file
    def initialize(id)
      @path_name = file_resolver.find(id)
    end

    def render(args)
      options = decode_options!(args)

      image.combine_options do |c|
        c.crop options[:crop] if options[:crop]
        c.resize options[:size] if options[:size]
        if options[:rotation]
          c.virtual_pixel 'white'
          c.distort.+ 'srt', options[:rotation]
        end

        case options[:quality]
        when 'grey'
          c.colorspace "Gray"
        when 'bitonal'
          c.colorspace "Gray"
          c.type 'Bilevel'
        end
      end
      image.format(options[:format])
      image.to_blob
    end

    def info
      {height: image[:height], width: image[:width]}
    end

    private

      def decode_options!(args)
        options = args.with_indifferent_access
        raise ArgumentError, 'You must provide a format' unless options[:format]
        options[:crop] = decode_region(options.delete(:region))
        options[:size] = decode_size(options.delete(:size))
        options[:quality] = decode_quality(options[:quality])
        options[:rotation] = decode_rotation(options[:rotation])
        validate_format!(options[:format])
        options
      end

      def decode_quality(quality)
        return if quality.nil? || ['native', 'color'].include?(quality)
        return quality if ['bitonal', 'grey'].include?(quality)
        raise InvalidAttributeError, "Unsupported quality: #{quality}" 
      end

      def decode_rotation(rotation)
        return if rotation.nil? || rotation == '0'
        begin
          Float(rotation)
        rescue ArgumentError
          raise InvalidAttributeError, "Unsupported rotation: #{rotation}"
        end
      end

      def validate_format!(format)
        raise InvalidAttributeError, "Unsupported format: #{format}" unless OUTPUT_FORMATS.include?(format)

      end

      def decode_region(region)
        if region.nil? || region == 'full'
          nil 
        elsif md = /^pct:(\d+),(\d+),(\d+),(\d+)$/.match(region)
          # Image magic can't do percentage offsets, so we have to calculate it
          offset_x = (image[:width] * Integer(md[1]).to_f / 100).round
          offset_y = (image[:height] * Integer(md[2]).to_f / 100).round
          "#{md[3]}%x#{md[4]}+#{offset_x}+#{offset_y}"
        elsif md = /^(\d+),(\d+),(\d+),(\d+)$/.match(region)
          "#{md[3]}x#{md[4]}+#{md[1]}+#{md[2]}"
        else
          raise InvalidAttributeError, "Invalid region: #{region}"
        end
      end

      def decode_size(size)
        if size.nil? || size == 'full'
          nil
        elsif md = /^,(\d+)$/.match(size)
          "x#{md[1]}"
        elsif md = /^(\d+),$/.match(size)
          "#{md[1]}"
        elsif md = /^pct:(\d+(.\d+)?)$/.match(size)
          "#{md[1]}%"
        elsif md = /^(\d+),(\d+)$/.match(size)
          "#{md[1]}x#{md[2]}!"
        elsif md = /^!(\d+),(\d+)$/.match(size)
          "#{md[1]}x#{md[2]}"
        else
          raise InvalidAttributeError, "Invalid size: #{size}"
        end
      end

      def image
        begin
          @image ||= MiniMagick::Image.open(path_name)
        rescue Errno::ENOENT => e
          Rails.logger.error "Unable to find #{path_name}"
          Rails.logger.error e.backtrace
          raise Riiif::Error, "Unable to find #{path_name}"
        rescue MiniMagick::Error => e
          Rails.logger.error "Error trying to open #{path_name}"
          Rails.logger.error e.backtrace
          raise Riiif::Error, "Unable to open the image #{path_name}"
        end
      end
  end
end
