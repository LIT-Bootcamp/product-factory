require "digest"
require "pathname"
require "tempfile"

module ProductFactory
  class ManagedFiles
    RESOLUTIONS = %w[keep_local take_upstream manual_merge].freeze

    def initialize(sources:)
      @sources = sources.to_h do |target, source|
        [target.to_s.dup.freeze, source.to_s.dup.freeze]
      end.freeze
    end

    def plan(target_root:, installed_hashes:, resolutions: {})
      installed_hashes = string_keyed(installed_hashes)
      resolutions = normalized_resolutions(resolutions)
      paths = (@sources.keys | installed_hashes.keys).sort
      unknown_resolutions = resolutions.keys - paths
      unless unknown_resolutions.empty?
        raise ValidationError, "resolution targets unknown path: #{unknown_resolutions.first}"
      end

      operations = []
      conflicts = []
      next_hashes = {}

      paths.each do |path|
        local = target_hash(target_root, path)
        installed = installed_hashes[path]
        upstream = nil
        bytes = nil
        mode = nil

        if @sources.key?(path)
          bytes, mode = read_source(@sources.fetch(path))
          upstream = Digest::SHA256.hexdigest(bytes)
          decision = refresh_decision(installed:, local:, upstream:)
        else
          decision = removal_decision(installed:, local:)
        end

        if decision == :conflict
          resolution, merged_hash = resolutions.fetch(path, [nil, nil])

          case resolution
          when "keep_local"
            next_hashes[path] = upstream if upstream
          when "take_upstream"
            if upstream
              operations << write_operation(path, bytes, mode, expected_local_hash: local, reason: resolution)
              next_hashes[path] = upstream
            else
              operations << Operation.new(
                kind: "delete_file",
                target: path,
                attributes: { "expected_local_hash" => local, "reason" => resolution }
              )
            end
          when "manual_merge"
            if merged_hash && local == merged_hash
              next_hashes[path] = upstream if upstream
            else
              conflicts << conflict(path, installed, local, upstream, resolution)
              next_hashes[path] = installed if installed
            end
          else
            conflicts << conflict(path, installed, local, upstream, resolution)
            next_hashes[path] = installed if installed
          end

          next
        end

        case decision
        when :write_upstream
          operations << write_operation(path, bytes, mode, expected_local_hash: local)
          next_hashes[path] = upstream
        when :preserve_local, :adopt, :noop
          next_hashes[path] = upstream
        when :delete_upstream
          operations << Operation.new(
            kind: "delete_file",
            target: path,
            attributes: { "expected_local_hash" => local }
          )
        when :removed
          nil
        end
      end

      { operations:, conflicts:, next_hashes: }
    end

    def apply(operation, target_root:)
      root = validated_target_root(target_root)
      destination = target_path(root, operation.target)

      case operation.kind
      when "write_file"
        apply_write(operation, root, destination)
      when "delete_file"
        apply_delete(root, destination)
      else
        raise ValidationError, "unsupported managed-file operation: #{operation.kind}"
      end

      nil
    end

    def current_hash(target_root:, path:) = current_state(target_root:, path:)&.fetch(:hash)

    def current_state(target_root:, path:)
      root = validated_target_root(target_root)
      destination = target_path(root, path)
      return unless File.exist?(destination)

      File.open(destination, File::RDONLY | File::NOFOLLOW) do |file|
        stat = file.stat
        raise ValidationError, "managed target is not a file: #{path}" unless stat.file?

        { hash: Digest::SHA256.hexdigest(file.binmode.read), mode: stat.mode & 0o7777 }
      end
    rescue Errno::ELOOP
      raise ValidationError, "managed target is a symlink: #{path}"
    end

    private

    def string_keyed(values)
      values.to_h { |path, value| [path.to_s, value] }
    end

    def normalized_resolutions(values)
      string_keyed(values).to_h do |path, value|
        choice, merged_hash =
          case value
          when String
            [value, nil]
          when Hash
            [
              value["resolution"] || value[:resolution] || value["choice"] || value[:choice],
              value["merged_hash"] || value[:merged_hash]
            ]
          else
            [value, nil]
          end

        unless RESOLUTIONS.include?(choice)
          raise ValidationError, "invalid resolution for #{path}: #{choice.inspect}"
        end
        if choice == "manual_merge" && merged_hash && !merged_hash.match?(/\A[0-9a-f]{64}\z/)
          raise ValidationError, "invalid merged hash for #{path}"
        end

        [path, [choice, merged_hash]]
      end
    end

    def refresh_decision(installed:, local:, upstream:)
      if installed.nil?
        local.nil? ? :write_upstream : (local == upstream ? :adopt : :conflict)
      elsif local == installed && upstream != installed
        :write_upstream
      elsif local != installed && upstream == installed
        :preserve_local
      elsif local == upstream
        :adopt
      elsif local != installed && upstream != installed
        :conflict
      else
        :noop
      end
    end

    def removal_decision(installed:, local:)
      return :removed if installed.nil? || local.nil?
      return :delete_upstream if local == installed

      :conflict
    end

    def conflict(path, installed, local, upstream, resolution)
      {
        "path" => path,
        "installed_hash" => installed,
        "local_hash" => local,
        "upstream_hash" => upstream,
        "resolution" => resolution
      }
    end

    def write_operation(path, bytes, mode, expected_local_hash:, reason: nil)
      attributes = {
        "content_base64" => [bytes].pack("m0"),
        "expected_local_hash" => expected_local_hash,
        "mode" => mode
      }
      attributes["reason"] = reason if reason
      Operation.new(
        kind: "write_file",
        target: path,
        attributes:
      )
    end

    def read_source(path)
      unless Pathname.new(path).absolute?
        raise ValidationError, "managed source must be absolute: #{path}"
      end

      stat = source_stat(path)
      raise ValidationError, "managed source is not a file: #{path}" unless stat.file?

      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened_stat = file.stat
        raise ValidationError, "managed source is not a file: #{path}" unless opened_stat.file?

        [file.binmode.read, opened_stat.mode & 0o7777]
      end
    rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES => error
      raise ValidationError, "cannot read managed source #{path}: #{error.message}"
    end

    def source_stat(path)
      current = File::SEPARATOR
      stat = nil

      Pathname.new(path).each_filename do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        raise ValidationError, "managed source path contains a symlink: #{path}" if stat.symlink?
      end

      stat
    end

    def target_hash(target_root, path)
      current_state(target_root:, path:)&.fetch(:hash)
    end

    def validated_target_root(target_root)
      root = File.expand_path(target_root)
      stat = File.lstat(root)
      raise ValidationError, "target root is a symlink: #{target_root}" if stat.symlink?
      raise ValidationError, "target root is not a directory: #{target_root}" unless stat.directory?

      root
    rescue Errno::ENOENT
      raise ValidationError, "target root does not exist: #{target_root}"
    end

    def target_path(root, relative_path)
      validate_relative_path(relative_path)
      destination = File.expand_path(relative_path, root)
      prefix = "#{root}#{File::SEPARATOR}"
      unless destination.start_with?(prefix)
        raise ValidationError, "unsafe managed target path: #{relative_path}"
      end

      current = root
      parts = relative_path.split(File::SEPARATOR)
      parts.each_with_index do |part, index|
        current = File.join(current, part)
        stat = File.lstat(current)
        raise ValidationError, "managed target is a symlink: #{relative_path}" if stat.symlink?
        if index < parts.length - 1 && !stat.directory?
          raise ValidationError, "managed target ancestor is not a directory: #{relative_path}"
        end
      rescue Errno::ENOENT
        break
      end

      destination
    end

    def validate_relative_path(path)
      parts = path.to_s.split(File::SEPARATOR, -1)
      unsafe = path.to_s.empty? ||
        path.to_s.include?("\0") ||
        Pathname.new(path.to_s).absolute? ||
        parts.any? { |part| part.empty? || part == "." || part == ".." }
      raise ValidationError, "unsafe managed target path: #{path}" if unsafe
    end

    def apply_write(operation, root, destination)
      attributes = operation.attributes
      unless attributes.is_a?(Hash) &&
          attributes["content_base64"].is_a?(String) &&
          attributes["mode"].is_a?(Integer) &&
          attributes["mode"].between?(0, 0o7777)
        raise ValidationError, "invalid write operation for #{operation.target}"
      end

      encoded = attributes.fetch("content_base64")
      mode = attributes.fetch("mode")
      bytes = encoded.unpack1("m0")
      ensure_destination_directory(root, File.dirname(destination))
      destination = target_path(root, operation.target)
      if File.exist?(destination) && !File.lstat(destination).file?
        raise ValidationError, "managed target is not a file: #{operation.target}"
      end

      Tempfile.create([".product-factory-", ".tmp"], File.dirname(destination)) do |temp|
        temp.binmode
        temp.write(bytes)
        temp.flush
        temp.fsync
        temp.chmod(mode)
        File.rename(temp.path, destination)
      end
    rescue KeyError, ArgumentError => error
      raise ValidationError, "invalid write operation for #{operation.target}: #{error.message}"
    end

    def ensure_destination_directory(root, directory)
      return if directory == root

      relative = directory.delete_prefix("#{root}#{File::SEPARATOR}")
      current = root
      relative.split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        begin
          stat = File.lstat(current)
        rescue Errno::ENOENT
          begin
            Dir.mkdir(current)
          rescue Errno::EEXIST
            nil
          end
          stat = File.lstat(current)
        end

        raise ValidationError, "managed target ancestor is a symlink: #{current}" if stat.symlink?
        raise ValidationError, "managed target ancestor is not a directory: #{current}" unless stat.directory?
      end
    end

    def apply_delete(root, destination)
      if File.exist?(destination)
        raise ValidationError, "managed target is not a file: #{destination}" unless File.lstat(destination).file?

        File.delete(destination)
      end

      directory = File.dirname(destination)
      while directory != root
        begin
          Dir.rmdir(directory)
        rescue Errno::ENOTEMPTY, Errno::ENOENT
          break
        end
        directory = File.dirname(directory)
      end
    end
  end
end
