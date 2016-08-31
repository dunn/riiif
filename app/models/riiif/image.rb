require 'digest/md5'
module Riiif
  class Image

    class_attribute :file_resolver, :info_service, :authorization_service
    self.file_resolver = FileSystemFileResolver.new
    self.authorization_service = NilAuthorizationService

    OUTPUT_FORMATS = %w(jpg png).freeze

    attr_reader :id

    # @param [String] id The identifier of the file to be looked up.
    # @param [Riiif::File] file Optional: The Riiif::File to use instead of looking one up.
    def initialize(id, file = nil)
      @id = id
      @image = file if file.present?
    end

    def image
      @image ||= file_resolver.find(id)
    end

    def render(args)
      options = decode_options!(args)
      Rails.cache.fetch(Image.cache_key(id, options), compress: true, expires_in: Image.expires_in) do
        image.extract(options)
      end
    end

    class << self
      def expires_in
        Riiif::Engine.config.cache_duration_in_days.days
      end


      def cache_key(id, options)
        str = options.merge(id: id).delete_if { |_, v| v.nil? }.to_s
        # Use a MD5 digest to ensure the keys aren't too long.
        Digest::MD5.hexdigest(str)
      end
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
        return if quality.nil? || %w(default color).include?(quality)
        return quality if %w(bitonal grey).include?(quality)
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
          offset_x = (image.info[:width] * Integer(md[1]).to_f / 100).round
          offset_y = (image.info[:height] * Integer(md[2]).to_f / 100).round
          "#{md[3]}%x#{md[4]}+#{offset_x}+#{offset_y}"
        elsif md = /^(\d+),(\d+),(\d+),(\d+)$/.match(region)
          "#{md[3]}x#{md[4]}+#{md[1]}+#{md[2]}"
        elsif region == 'square'
          w = image.info[:width]
          h = image.info[:height]
          min, max = [w, h].minmax

          offset = (max - min) / 2
          if h >= w
            "#{min}x#{min}+0+#{offset}"
          else
            "#{min}x#{min}+#{offset}+0"
          end
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
          (md[1]).to_s
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

  end
end
