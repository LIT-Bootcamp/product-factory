RSpec.describe ProductFactory::ManagedFiles do
  it "implements the three-way refresh truth table" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        write(source, "managed/a.txt", "upstream-v1\n")
        files = described_class.new(sources: { "a.txt" => File.join(source, "managed/a.txt") })
        initial = files.plan(target_root: target, installed_hashes: {})
        files.apply(initial.fetch(:operations).first, target_root: target)
        old_hashes = initial.fetch(:next_hashes)

        expect(files.plan(target_root: target, installed_hashes: old_hashes).fetch(:operations)).to be_empty

        write(target, "a.txt", "local-only\n")
        local_only = files.plan(target_root: target, installed_hashes: old_hashes)
        expect(local_only.fetch(:operations)).to be_empty
        expect(local_only.fetch(:conflicts)).to be_empty

        write(source, "managed/a.txt", "upstream-v2\n")
        conflict = files.plan(target_root: target, installed_hashes: old_hashes)
        expect(conflict.fetch(:conflicts)).to contain_exactly(
          include(
            "path" => "a.txt",
            "installed_hash" => old_hashes.fetch("a.txt"),
            "local_hash" => kind_of(String),
            "upstream_hash" => kind_of(String),
            "resolution" => nil
          )
        )

        resolved = files.plan(
          target_root: target,
          installed_hashes: old_hashes,
          resolutions: { "a.txt" => "take_upstream" }
        )
        expect(resolved.fetch(:conflicts)).to be_empty
        expect(resolved.fetch(:operations).map(&:target)).to eq(["a.txt"])
      end
    end
  end

  it "keeps manual merges conflicted until the recorded merged hash matches" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        write(source, "a.txt", "upstream-v2\n")
        write(target, "a.txt", "local-v2\n")
        installed = Digest::SHA256.hexdigest("shared-v1\n")
        merged = Digest::SHA256.hexdigest("merged\n")
        files = described_class.new(sources: { "a.txt" => File.join(source, "a.txt") })
        resolution = { "a.txt" => { "resolution" => "manual_merge", "merged_hash" => merged } }

        unresolved = files.plan(
          target_root: target,
          installed_hashes: { "a.txt" => installed },
          resolutions: resolution
        )
        expect(unresolved.fetch(:conflicts).first.fetch("resolution")).to eq("manual_merge")

        write(target, "a.txt", "merged\n")
        resolved = files.plan(
          target_root: target,
          installed_hashes: { "a.txt" => installed },
          resolutions: resolution
        )
        expect(resolved.fetch(:conflicts)).to be_empty
        expect(resolved.fetch(:operations)).to be_empty

        expect do
          files.plan(
            target_root: target,
            installed_hashes: { "a.txt" => installed },
            resolutions: { "a.txt" => "overwrite" }
          )
        end.to raise_error(ProductFactory::ValidationError, /invalid resolution/)
      end
    end
  end

  it "plans upstream removals only for previously managed unchanged files" do
    in_tmp_repo do |target|
      write(target, "empty/a.txt", "managed\n")
      write(target, "kept/b.txt", "changed\n")
      write(target, "local/c.txt", "never managed\n")
      installed = {
        "empty/a.txt" => Digest::SHA256.hexdigest("managed\n"),
        "kept/b.txt" => Digest::SHA256.hexdigest("original\n")
      }
      files = described_class.new(sources: {})

      plan = files.plan(target_root: target, installed_hashes: installed)

      expect(plan.fetch(:operations).map { |operation| [operation.kind, operation.target] })
        .to eq([["delete_file", "empty/a.txt"]])
      expect(plan.fetch(:conflicts).map { |conflict| conflict.fetch("path") }).to eq(["kept/b.txt"])
      expect(plan.fetch(:next_hashes)).to eq("kept/b.txt" => installed.fetch("kept/b.txt"))

      files.apply(plan.fetch(:operations).first, target_root: target)

      expect(File.exist?(File.join(target, "empty/a.txt"))).to eq(false)
      expect(Dir.exist?(File.join(target, "empty"))).to eq(false)
      expect(File.read(File.join(target, "kept/b.txt"))).to eq("changed\n")
      expect(File.read(File.join(target, "local/c.txt"))).to eq("never managed\n")
    end
  end

  it "plans deterministically without mutation and applies captured bytes and mode by replacement" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        write(source, "a.txt", "captured-a\n")
        write(source, "b.txt", "captured-b\n")
        File.chmod(0o751, File.join(source, "a.txt"))
        source_map = {
          "b.txt" => File.join(source, "b.txt"),
          "a.txt" => File.join(source, "a.txt")
        }
        files = described_class.new(sources: source_map)
        source_map.clear

        before = Dir.children(target)
        plan = files.plan(target_root: target, installed_hashes: {})

        expect(Dir.children(target)).to eq(before)
        expect(plan.fetch(:operations).map(&:target)).to eq(%w[a.txt b.txt])
        operation = plan.fetch(:operations).first
        expect(operation.attributes.fetch("content_base64").unpack1("m0")).to eq("captured-a\n")
        expect(operation.attributes.fetch("mode")).to eq(0o751)

        write(target, "a.txt", "old\n")
        old_inode = File.stat(File.join(target, "a.txt")).ino
        write(source, "a.txt", "changed-after-plan\n")
        files.apply(operation, target_root: target)

        expect(File.binread(File.join(target, "a.txt"))).to eq("captured-a\n")
        expect(File.stat(File.join(target, "a.txt")).mode & 0o777).to eq(0o751)
        expect(File.stat(File.join(target, "a.txt")).ino).not_to eq(old_inode)
        expect(Dir.children(target)).to eq(["a.txt"])
      end
    end
  end

  it "rejects traversal and absolute targets without writing outside the target root" do
    in_tmp_repo do |container|
      target = File.join(container, "target")
      Dir.mkdir(target)
      source = File.join(container, "source.txt")
      File.write(source, "safe\n")
      safe_files = described_class.new(sources: { "safe.txt" => source })
      safe_operation = safe_files.plan(target_root: target, installed_hashes: {}).fetch(:operations).first

      ["../escape.txt", File.join(container, "absolute.txt")].each do |path|
        files = described_class.new(sources: { path => source })
        expect { files.plan(target_root: target, installed_hashes: {}) }
          .to raise_error(ProductFactory::ValidationError, /unsafe managed target path/)

        operation = ProductFactory::Operation.new(
          kind: safe_operation.kind,
          target: path,
          attributes: safe_operation.attributes
        )
        expect { safe_files.apply(operation, target_root: target) }
          .to raise_error(ProductFactory::ValidationError, /unsafe managed target path/)
      end

      expect(File.exist?(File.join(container, "escape.txt"))).to eq(false)
      expect(File.exist?(File.join(container, "absolute.txt"))).to eq(false)
    end
  end

  it "rejects source, target, and target-ancestor symlinks during planning and apply" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        in_tmp_repo do |outside|
          write(source, "real.txt", "upstream\n")
          File.symlink(File.join(source, "real.txt"), File.join(source, "linked.txt"))
          linked_source = described_class.new(sources: { "a.txt" => File.join(source, "linked.txt") })
          expect { linked_source.plan(target_root: target, installed_hashes: {}) }
            .to raise_error(ProductFactory::ValidationError, /source path contains a symlink/)

          files = described_class.new(sources: { "a.txt" => File.join(source, "real.txt") })
          operation = files.plan(target_root: target, installed_hashes: {}).fetch(:operations).first
          write(outside, "victim.txt", "outside\n")
          File.symlink(File.join(outside, "victim.txt"), File.join(target, "a.txt"))

          expect { files.plan(target_root: target, installed_hashes: {}) }
            .to raise_error(ProductFactory::ValidationError, /target is a symlink/)
          expect { files.apply(operation, target_root: target) }
            .to raise_error(ProductFactory::ValidationError, /target is a symlink/)
          expect(File.read(File.join(outside, "victim.txt"))).to eq("outside\n")

          nested_files = described_class.new(sources: { "nested/a.txt" => File.join(source, "real.txt") })
          File.unlink(File.join(target, "a.txt"))
          nested_operation = nested_files.plan(target_root: target, installed_hashes: {}).fetch(:operations).first
          File.symlink(outside, File.join(target, "nested"))

          expect { nested_files.plan(target_root: target, installed_hashes: {}) }
            .to raise_error(ProductFactory::ValidationError, /target is a symlink/)
          expect { nested_files.apply(nested_operation, target_root: target) }
            .to raise_error(ProductFactory::ValidationError, /target is a symlink/)
          expect(File.exist?(File.join(outside, "a.txt"))).to eq(false)
        end
      end
    end
  end

  it "rejects malformed write-operation attributes with a validation error" do
    in_tmp_repo do |target|
      [
        nil,
        [],
        { "content_base64" => 123, "mode" => 0o644 }
      ].each do |attributes|
        operation = ProductFactory::Operation.new(
          kind: "write_file",
          target: "a.txt",
          attributes: attributes
        )

        expect { described_class.new(sources: {}).apply(operation, target_root: target) }
          .to raise_error(ProductFactory::ValidationError)
      end
    end
  end

  it "rejects a source file reached through a symlinked parent directory" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        in_tmp_repo do |outside|
          write(outside, "nested/real.txt", "upstream\n")
          File.symlink(outside, File.join(source, "linked-parent"))
          files = described_class.new(
            sources: {
              "a.txt" => File.join(source, "linked-parent", "nested", "real.txt")
            }
          )

          expect { files.plan(target_root: target, installed_hashes: {}) }
            .to raise_error(ProductFactory::ValidationError, /source path contains a symlink/)
        end
      end
    end
  end
end
