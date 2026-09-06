# frozen_string_literal: true

module ProductFactory
  class Distribution
    REQUIRED_FILES = %w[
      lib/product_factory.rb
      templates/config.yml
      templates/project/bin/product-factory
      templates/project/.product-factory/spec/integration_spec.rb
      templates/project/.product-factory/schemas/config-v1.yml
      templates/project/.product-factory/schemas/installation-v1.yml
      templates/project/.product-factory/schemas/provisioning-v1.yml
    ].freeze

    def initialize(root)
      @root = File.expand_path(root)
    end

    def factory_sources
      validate!
      library_sources.merge(config_source).merge(project_sources)
    end

    def config_bytes
      File.binread(path("templates/config.yml"))
    end

    def provisioning_schema_bytes
      File.binread(path("templates/project/.product-factory/schemas/provisioning-v1.yml"))
    end

    private

    def validate!
      complete = File.directory?(path("lib")) &&
                 File.directory?(path("templates/project")) &&
                 REQUIRED_FILES.all? { |relative_path| File.file?(path(relative_path)) }
      raise ValidationError, "Product Factory distribution is incomplete" unless complete
    end

    def library_sources
      Dir.glob(path("lib/**/*.rb")).to_h do |source|
        [File.join(".product-factory/runtime", relative_path(source)), source]
      end
    end

    def config_source
      { ".product-factory/runtime/templates/config.yml" => path("templates/config.yml") }
    end

    def project_sources
      files = Dir.glob(path("templates/project/**/*"), File::FNM_DOTMATCH).select { |source| File.file?(source) }
      sources = files.to_h do |source|
        relative = source.delete_prefix("#{path('templates/project')}/")
        [relative, source]
      end
      sources.dup.each do |relative, source|
        sources[File.join(".product-factory/runtime/templates/project", relative)] = source
      end
      sources
    end

    def relative_path(source) = source.delete_prefix("#{@root}/")
    def path(relative) = File.join(@root, relative)
  end
end
