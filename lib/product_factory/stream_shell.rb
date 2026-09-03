# frozen_string_literal: true

require "thor"

module ProductFactory
  class StreamShell < Thor::Shell::Basic
    def initialize(output, error)
      super()
      @stdout = output
      @stderr = error
    end

    attr_reader :stdout, :stderr
  end
end
