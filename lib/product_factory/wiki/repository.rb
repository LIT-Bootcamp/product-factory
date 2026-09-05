# frozen_string_literal: true

module ProductFactory
  module Wiki
    class Repository
      OWNED_PAGES = %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs].map { |name| "#{name}.md" }.freeze

      def initialize(organization:, repository:, shell:, remote: nil)
        @shell = shell
        @remote = remote || "https://github.com/#{organization}/#{repository}.wiki.git"
      end

      def snapshot
        @snapshot ||= with_checkout { |checkout| read_checkout(checkout) }
      end

      def apply(operation)
        desired = operation.attributes.fetch("pages")
        validate_pages!(desired)
        with_checkout do |checkout|
          current = read_checkout(checkout)
          if desired?(current, desired)
            @snapshot = current
            return true
          end

          verify_head!(operation, current)
          write_pages(checkout, desired)
          commit_and_push(checkout, desired.keys)
        end
        @snapshot = nil
        raise ValidationError, "Wiki verification failed" unless matches?(operation)

        true
      end

      def matches?(operation)
        @snapshot = nil
        desired?(snapshot, operation.attributes.fetch("pages"))
      end

      def head = snapshot.fetch("head")

      def page_hashes
        snapshot.fetch("pages").slice(*OWNED_PAGES).transform_values { |content| Digest::SHA256.hexdigest(content) }
      end

      private

      def with_checkout
        Dir.mktmpdir("product-factory-wiki") do |directory|
          checkout = File.join(directory, "wiki")
          clone(checkout)
          yield checkout
        end
      end

      def clone(checkout)
        run!(
          "git", "-c", "credential.https://github.com.helper=!gh auth git-credential",
          "clone", "--quiet", @remote, checkout
        )
      end

      def read_checkout(checkout)
        home = File.join(checkout, "Home.md")
        raise missing_home unless File.file?(home)

        head = run!("git", "rev-parse", "HEAD", chdir: checkout).strip
        pages = Dir.glob(File.join(checkout, "*.md")).to_h do |path|
          [File.basename(path), File.binread(path)]
        end
        immutable("head" => head, "pages" => pages)
      end

      def write_pages(checkout, pages)
        pages.each do |name, content|
          Tempfile.create([".wiki-", ".tmp"], checkout) do |file|
            file.binmode
            file.write(content)
            file.flush
            file.fsync
            File.rename(file.path, File.join(checkout, name))
          end
        end
      end

      def commit_and_push(checkout, pages)
        run!("git", "add", "--", *pages, chdir: checkout)
        run!(
          "git", "-c", "user.name=Product Factory",
          "-c", "user.email=product-factory@users.noreply.github.com",
          "commit", "-m", "Update Product Factory pages", chdir: checkout
        )
        run!("git", "push", "origin", "HEAD", chdir: checkout)
      end

      def run!(*command, chdir: nil)
        output, error, status = @shell.capture3(*command, chdir:, stdin_data: nil)
        return output if status.success?

        raise failure(error)
      end

      def validate_pages!(pages)
        valid = pages.is_a?(Hash) && pages.keys.all? { |name| OWNED_PAGES.include?(name) } &&
                pages.values.all?(String)
        raise ValidationError, "invalid Wiki pages" unless valid
      end

      def verify_head!(operation, current)
        return if current.fetch("head") == operation.attributes.fetch("expected_head")

        raise ConflictError, "Wiki changed after planning"
      end

      def desired?(snapshot, desired)
        desired.all? { |name, content| snapshot.dig("pages", name) == content }
      end

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
