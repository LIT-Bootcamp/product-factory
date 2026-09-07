# frozen_string_literal: true

module ProductFactory
  module Artifacts
    # rubocop:disable-next Metrics/ClassLength
    class Wiki
      PAGES = {
        "index" => "Product-Factory.md",
        "setup-log" => "Setup-Log.md",
        "ideas/index" => "Ideas.md",
        "epics/index" => "Epics.md",
        "tickets/index" => "Tickets.md",
        "research/index" => "Research.md",
        "factory-runs/index" => "Factory-Runs.md"
      }.freeze

      def initialize(organization:, repository:, shell:, remote: nil)
        @shell = shell
        @remote = remote || "https://github.com/#{organization}/#{repository}.wiki.git"
      end

      def snapshot = @snapshot ||= with_checkout { |checkout| read_checkout(checkout) }

      def apply(operation)
        validate_operation!(operation)
        desired = operation.attributes.fetch("documents")
        with_checkout do |checkout|
          current = read_checkout(checkout)
          if desired?(current, desired)
            verify_revision!(operation, current, checkout:)
            @snapshot = current
            return true
          end

          verify_revision!(operation, current)
          write_documents(checkout, desired)
          commit_and_push(checkout, operation)
        end
        @snapshot = nil
        raise ValidationError, "Artifacts verification failed" unless matches?(operation)

        true
      end

      def matches?(operation)
        validate_operation!(operation)
        @snapshot = nil
        snapshot_matches?(snapshot, operation)
      end

      def revision = snapshot.fetch("revision")

      def document_hashes = snapshot.fetch("documents").transform_values { |content| Digest::SHA256.hexdigest(content) }

      private

      def with_checkout
        Dir.mktmpdir("product-factory-wiki") do |directory|
          checkout = File.join(directory, "wiki")
          clone(checkout)
          yield checkout
        end
      end

      def clone(checkout)
        run!("git", "-c", "credential.https://github.com.helper=!gh auth git-credential", "clone", "--quiet",
             @remote, checkout)
      end

      def read_checkout(checkout)
        raise missing_home unless read_page(checkout, "Home.md")

        revision = run!("git", "rev-parse", "HEAD", chdir: checkout).strip
        documents = PAGES.filter_map do |document, page|
          content = read_page(checkout, page)
          [document, content] if content
        end.to_h
        legacy_owned_documents = documents.keys.select do |document|
          documents.fetch(document).include?(legacy_marker(PAGES.fetch(document)))
        end
        immutable("revision" => revision, "documents" => documents, "legacy_owned_documents" => legacy_owned_documents)
      end

      def read_page(checkout, page)
        path = File.join(checkout, page)
        stat = File.lstat(path)
        raise ValidationError, "artifact page is a symlink: #{page}" if stat.symlink?
        raise ValidationError, "artifact page is not a regular file: #{page}" unless stat.file?

        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          raise ValidationError, "artifact page is not a regular file: #{page}" unless file.stat.file?

          file.binmode.read
        end
      rescue Errno::ENOENT
        nil
      rescue Errno::ELOOP
        raise ValidationError, "artifact page is a symlink: #{page}"
      rescue Errno::EACCES, Errno::EAGAIN, Errno::EISDIR, Errno::ENODEV, Errno::ENOTDIR, Errno::ENXIO, Errno::EPERM
        raise ValidationError, "cannot read artifact page: #{page}"
      end

      def write_documents(checkout, documents)
        documents.each do |document, content|
          Tempfile.create([".wiki-", ".tmp"], checkout) do |file|
            file.binmode
            file.write(content)
            file.flush
            file.fsync
            File.rename(file.path, File.join(checkout, PAGES.fetch(document)))
          end
        end
      end

      def commit_and_push(checkout, operation)
        pages = operation.attributes.fetch("documents").keys.map { |document| PAGES.fetch(document) }
        run!("git", "add", "--", *pages, chdir: checkout)
        run!(
          "git", "-c", "user.name=Product Factory",
          "-c", "user.email=product-factory@users.noreply.github.com",
          "commit", "-m", "Update Product Factory artifacts",
          "-m", operation_trailer(operation), chdir: checkout
        )
        run!("git", "push", "origin", "HEAD", chdir: checkout)
      end

      def completed_commit?(checkout, operation)
        expected_parent = operation.attributes.fetch("expected_revision")
        parents = run!("git", "show", "-s", "--format=%P", "HEAD", chdir: checkout).strip
        message = run!("git", "show", "-s", "--format=%B", "HEAD", chdir: checkout).strip
        parents == expected_parent && message == commit_message(operation)
      end

      def commit_message(operation) = "Update Product Factory artifacts\n\n#{operation_trailer(operation)}"
      def operation_trailer(operation) = "Product-Factory-Operation: #{operation.id}"

      def run!(*command, chdir: nil)
        output, error, status = @shell.capture3(*command, chdir:, stdin_data: nil)
        return output if status.success?

        raise failure(error)
      end

      def validate_operation!(operation)
        attributes = operation.attributes
        valid = Artifacts.valid_operation?(operation) && attributes["adapter"] == "wiki"
        raise ValidationError, "invalid Artifacts operation" unless valid
      end

      def verify_revision!(operation, current, checkout: nil)
        return if current.fetch("revision") == operation.attributes.fetch("expected_revision")
        return if checkout && completed_commit?(checkout, operation)

        raise ConflictError, "Artifacts changed after planning"
      end

      def desired?(state, desired) = desired.all? { |document, content| state.dig("documents", document) == content }

      def snapshot_matches?(state, operation)
        desired = operation.attributes.fetch("documents")
        expected = operation.attributes.fetch("expected_hashes")
        PAGES.keys.all? do |document|
          content = state.fetch("documents")[document]
          desired.key?(document) ? content == desired.fetch(document) : digest(content) == expected.fetch(document)
        end
      end

      def digest(content) = content && Digest::SHA256.hexdigest(content)

      def legacy_marker(page) = "<!-- product-factory:v1:wiki:#{File.basename(page, '.md')} -->"

      def missing_home
        ExternalFailure.new(
          failed_rule: "wiki_home_required", responsible_component: "wiki prerequisite",
          root_cause: "GitHub Wiki has no Home page", impact: "setup planning stopped before mutation",
          recovery_action: "Create the Home page in GitHub Wiki, then rerun product-factory setup"
        )
      end

      def failure(cause)
        ExternalFailure.new(
          failed_rule: "wiki_git_command", responsible_component: "wiki",
          root_cause: cause.to_s.strip, impact: "Wiki state was not read or changed",
          recovery_action: "fix Wiki Git access, then rerun product-factory setup"
        )
      end

      def immutable(value) = JSON.parse(JSON.generate(value), freeze: true)
    end
  end
end
