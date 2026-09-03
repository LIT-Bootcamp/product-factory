# frozen_string_literal: true

module FileHelpers
  def in_tmp_repo
    Dir.mktmpdir("product-factory-test") { |root| yield File.realpath(root) }
  end

  def write(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
