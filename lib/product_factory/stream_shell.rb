# frozen_string_literal: true

module ProductFactory
  class StreamShell < Thor::Shell::Basic
    def initialize(output, error)
      super()
      @stdout = output
      @stderr = error
    end

    attr_reader :stdout, :stderr

    def capture3(*command, chdir: nil, stdin_data: nil)
      options = {}
      options[:chdir] = chdir if chdir
      options[:stdin_data] = stdin_data if stdin_data
      Open3.capture3(*command, **options)
    end
  end
end
