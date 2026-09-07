# frozen_string_literal: true

module ProductFactory
  module Artifacts
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

      def snapshot
        @snapshot ||= begin
          documents = PATHS.filter_map do |document, _relative|
            content = read(document)
            [document, content] if content
          end.to_h
          immutable(
            "revision" => Digest::SHA256.hexdigest(JSON.generate(documents)),
            "documents" => documents
          )
        end
      end

      def apply(operation)
        validate_operation!(operation)
        desired = operation.attributes.fetch("documents")
        current = refresh_snapshot
        return true if desired?(current, desired)

        verify_revision!(operation, current)
        desired.each do |document, content|
          write(document, content) unless current.fetch("documents")[document] == content
        end
        @snapshot = nil
        raise ValidationError, "Artifacts verification failed" unless matches?(operation)

        true
      end

      def matches?(operation)
        validate_operation!(operation)
        desired?(refresh_snapshot, operation.attributes.fetch("documents"))
      end

      def revision = snapshot.fetch("revision")

      def document_hashes
        snapshot.fetch("documents").transform_values { |content| digest(content) }
      end

      private

      def refresh_snapshot
        @snapshot = nil
        snapshot
      end

      def read(document)
        validate_path!(document)
        File.open(physical_path(document), File::RDONLY | File::NOFOLLOW) do |file|
          raise ValidationError, "artifact target is not a regular file: #{document}" unless file.stat.file?

          file.binmode.read
        end
      rescue Errno::ENOENT
        nil
      rescue Errno::ELOOP
        raise ValidationError, "artifact target is a symlink: #{document}"
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

      def physical_path(document) = File.join(@root, PATHS.fetch(document))
      def relative_path(document) = File.join(@relative_root, PATHS.fetch(document))

      def desired?(current, desired)
        desired.all? { |document, content| current.fetch("documents")[document] == content }
      end

      def verify_revision!(operation, current)
        return if current.fetch("revision") == operation.attributes.fetch("expected_revision")

        expected = operation.attributes.fetch("expected_hashes")
        desired = operation.attributes.fetch("documents")
        safe = PATHS.keys.all? do |document|
          actual = digest(current.fetch("documents")[document])
          completed = desired.key?(document) && actual == digest(desired.fetch(document))
          actual == expected.fetch(document) || completed
        end
        raise ConflictError, "Artifacts changed after planning" unless safe
      end

      def validate_operation!(operation)
        attributes = operation.attributes
        valid = operation.kind == Operation::SYNC_ARTIFACTS && operation.target == "artifacts:documents" &&
                attributes["adapter"] == "repository" && attributes["expected_revision"].is_a?(String) &&
                valid_hashes?(attributes["expected_hashes"]) && valid_documents?(attributes["documents"])
        raise ValidationError, "invalid repository artifact operation" unless valid
      end

      def valid_hashes?(hashes)
        hashes.is_a?(Hash) && hashes.keys.sort == PATHS.keys.sort &&
          hashes.values.all? { |hash| hash.nil? || hash.match?(/\A[0-9a-f]{64}\z/) }
      end

      def valid_documents?(documents)
        documents.is_a?(Hash) && documents.keys.all? { |document| PATHS.key?(document) } &&
          documents.values.all?(String)
      end

      def digest(content) = content && Digest::SHA256.hexdigest(content)
      def immutable(value) = JSON.parse(JSON.generate(value), freeze: true)
    end
  end
end
