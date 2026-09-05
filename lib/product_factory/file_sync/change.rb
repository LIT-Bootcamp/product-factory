# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Change < Service
      def initialize(path:, source:, target:, installed_hash:, resolution:)
        super()
        @path = path
        @source = source
        @target = target
        @installed_hash = installed_hash
        @resolution_input = resolution
        @local_hash = target.hash(path)
      end

      def call
        resolution if @resolution_input
        @source ? update : remove
      end

      private

      def update
        @bytes, @mode = Source.read(@source)
        @upstream_hash = Digest::SHA256.hexdigest(@bytes)

        return initial unless @installed_hash
        return write_upstream if @local_hash == @installed_hash && @upstream_hash != @installed_hash
        return keep(@upstream_hash) if @local_hash != @installed_hash && @upstream_hash == @installed_hash
        return keep(@upstream_hash) if @local_hash == @upstream_hash
        return resolve if @local_hash != @installed_hash && @upstream_hash != @installed_hash

        keep(@upstream_hash)
      end

      def initial
        return write_upstream unless @local_hash
        return keep(@upstream_hash) if @local_hash == @upstream_hash

        resolve
      end

      def remove
        return result unless @installed_hash && @local_hash
        return delete_upstream if @local_hash == @installed_hash

        resolve
      end

      def resolve
        choice, merged_hash = resolution

        case choice
        when KEEP_LOCAL then keep(@upstream_hash)
        when TAKE_UPSTREAM then @upstream_hash ? write_upstream(TAKE_UPSTREAM) : delete_upstream(TAKE_UPSTREAM)
        when MANUAL_MERGE then accept_manual_merge(merged_hash)
        else conflict(choice)
        end
      end

      def resolution
        return @resolution if defined?(@resolution)

        choice, merged_hash = unpack_resolution
        if choice && !RESOLUTIONS.include?(choice)
          raise ValidationError, "invalid resolution for #{@path}: #{choice.inspect}"
        end
        if choice == MANUAL_MERGE && merged_hash && !merged_hash.match?(/\A[0-9a-f]{64}\z/)
          raise ValidationError, "invalid merged hash for #{@path}"
        end

        @resolution = [choice, merged_hash]
      end

      def unpack_resolution
        return [@resolution_input, nil] unless @resolution_input.is_a?(Hash)

        [
          @resolution_input["resolution"] || @resolution_input[:resolution] ||
            @resolution_input["choice"] || @resolution_input[:choice],
          @resolution_input["merged_hash"] || @resolution_input[:merged_hash]
        ]
      end

      def accept_manual_merge(merged_hash)
        return conflict(MANUAL_MERGE) unless merged_hash && @local_hash == merged_hash

        keep(@upstream_hash)
      end

      def write_upstream(reason = nil)
        attributes = {
          "content_base64" => [@bytes].pack("m0"),
          "expected_local_hash" => @local_hash,
          "mode" => @mode
        }
        attributes["reason"] = reason if reason
        operation = Operation.new(kind: Operation::WRITE_FILE, target: @path, attributes:)
        result(operation:, next_hash: @upstream_hash)
      end

      def delete_upstream(reason = nil)
        attributes = { "expected_local_hash" => @local_hash }
        attributes["reason"] = reason if reason
        operation = Operation.new(kind: Operation::DELETE_FILE, target: @path, attributes:)
        result(operation:)
      end

      def conflict(choice)
        details = {
          "path" => @path,
          "installed_hash" => @installed_hash,
          "local_hash" => @local_hash,
          "upstream_hash" => @upstream_hash,
          "resolution" => choice
        }
        result(conflict: details, next_hash: @installed_hash)
      end

      def keep(next_hash)
        result(next_hash:)
      end

      def result(operation: nil, conflict: nil, next_hash: nil)
        { path: @path, operation:, conflict:, next_hash: }
      end
    end
  end
end
