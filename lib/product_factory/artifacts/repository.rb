# frozen_string_literal: true

module ProductFactory
  module Artifacts
    # rubocop:disable-next Metrics/ClassLength
    class Repository
      PATHS = {
        "index" => "README.md",
        "setup-log" => "setup-log.md",
        "ideas/index" => "ideas/README.md",
        "epics/index" => "epics/README.md",
        "tickets/index" => "tickets/README.md",
        "research/index" => "research/README.md",
        "factory-runs/index" => "factory-runs/README.md"
      }.freeze

      def initialize(target_root:, root:)
        root_path = FileSync::Path.new(root: target_root, relative: root)
        @target_root = root_path.root
        @root = root_path.to_s
        @relative_root = root_path.relative
        @files = FileSync::Target.new(root: @target_root)
      end

      def snapshot(document_ids: Planner::DOCUMENT_IDS)
        document_ids = valid_document_ids!(document_ids)
        @document_ids = document_ids
        @snapshots ||= {}
        @snapshots[document_ids] ||= begin
          documents = document_ids.filter_map do |document|
            content = read(document)
            [document, content] if content
          end.to_h
          immutable(
            "revision" => Digest::SHA256.hexdigest(JSON.generate(documents)),
            "documents" => documents
          )
        end
      end

      def link(document) = mapped_path(document)

      def apply(operation)
        validate_operation!(operation)
        desired = operation.attributes.fetch("documents")
        current = refresh_snapshot(document_ids: operation.attributes.fetch("expected_hashes").keys)
        verify_revision!(operation, current)
        return true if desired?(current, desired)

        desired.each do |document, content|
          write(document, content) unless current.fetch("documents")[document] == content
        end
        @snapshots = nil
        raise ValidationError, "Artifacts verification failed" unless matches?(operation)

        true
      end

      def matches?(operation)
        validate_operation!(operation)
        snapshot_matches?(refresh_snapshot(document_ids: operation.attributes.fetch("expected_hashes").keys), operation)
      end

      def revision(document_ids: @document_ids || Planner::DOCUMENT_IDS) = snapshot(document_ids:).fetch("revision")

      def document_hashes(document_ids: @document_ids || Planner::DOCUMENT_IDS)
        snapshot(document_ids:).fetch("documents").transform_values { |content| digest(content) }
      end

      private

      def refresh_snapshot(document_ids:)
        @snapshots = nil
        snapshot(document_ids:)
      end

      def read(document)
        validate_path!(document)
        path = physical_path(document)
        validate_regular_file!(path, document)
        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          raise ValidationError, "artifact target is not a regular file: #{document}" unless file.stat.file?

          file.binmode.read
        end
      rescue Errno::ENOENT
        nil
      rescue Errno::ELOOP
        raise ValidationError, "artifact target is a symlink: #{document}"
      rescue Errno::EACCES, Errno::EAGAIN, Errno::EISDIR, Errno::ENODEV, Errno::ENOTDIR, Errno::ENXIO, Errno::EPERM
        raise ValidationError, "cannot read artifact target: #{document}"
      end

      def write(document, content)
        @files.apply(
          Operation.new(
            kind: Operation::WRITE_FILE,
            target: relative_path(document),
            attributes: { "content_base64" => [content].pack("m0"), "mode" => 0o644 }
          )
        )
      end

      def validate_path!(document)
        FileSync::Path.new(root: @target_root, relative: relative_path(document)).to_s
      end

      def validate_regular_file!(path, document)
        stat = File.lstat(path)
        raise ValidationError, "artifact target is a symlink: #{document}" if stat.symlink?
        raise ValidationError, "artifact target is not a regular file: #{document}" unless stat.file?
      end

      def physical_path(document) = File.join(@root, mapped_path(document))
      def relative_path(document) = File.join(@relative_root, mapped_path(document))

      def mapped_path(document)
        validate_document!(document)
        return PATHS.fetch(document) if PATHS.key?(document)

        path = document.end_with?("/index") ? "#{document.delete_suffix('/index')}/README.md" : "#{document}.md"
        raise ValidationError, "artifact document collides with a fixed setup path" if PATHS.value?(path)

        path
      end

      def desired?(current, desired)
        desired.all? { |document, content| current.fetch("documents")[document] == content }
      end

      def snapshot_matches?(current, operation)
        desired = operation.attributes.fetch("documents")
        expected = operation.attributes.fetch("expected_hashes")
        expected.all? do |document, hash|
          content = current.fetch("documents")[document]
          desired.key?(document) ? content == desired.fetch(document) : digest(content) == hash
        end
      end

      def verify_revision!(operation, current)
        return if current.fetch("revision") == operation.attributes.fetch("expected_revision")

        expected = operation.attributes.fetch("expected_hashes")
        desired = operation.attributes.fetch("documents")
        safe = expected.all? do |document, hash|
          actual = digest(current.fetch("documents")[document])
          completed = desired.key?(document) && actual == digest(desired.fetch(document))
          actual == hash || completed
        end
        raise ConflictError, "Artifacts changed after planning" unless safe
      end

      def validate_operation!(operation)
        attributes = operation.attributes
        valid = Artifacts.valid_operation?(operation) && attributes["adapter"] == "repository" &&
                unique_paths?(attributes["expected_hashes"].keys)
        raise ValidationError, "invalid repository artifact operation" unless valid
      end

      def unique_paths?(documents) = documents.map { |document| mapped_path(document) }.uniq.length == documents.length

      def valid_document_ids!(document_ids)
        unless document_ids.is_a?(Array) && document_ids.all? { |document| Artifacts.valid_document_id?(document) }
          raise ValidationError, "invalid artifact document"
        end

        document_ids.uniq.sort.freeze
      end

      def validate_document!(document)
        raise ValidationError, "invalid artifact document" unless Artifacts.valid_document_id?(document)
      end

      def digest(content) = content && Digest::SHA256.hexdigest(content)
      def immutable(value) = JSON.parse(JSON.generate(value), freeze: true)
    end
  end
end
