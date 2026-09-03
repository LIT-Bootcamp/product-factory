# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Decision
      def self.call(source_present:, installed:, local:, upstream:)
        return removal(installed:, local:) unless source_present
        return initial(local:, upstream:) unless installed
        return :write_upstream if local == installed && upstream != installed
        return :preserve_local if local != installed && upstream == installed
        return :adopt if local == upstream
        return :conflict if local != installed && upstream != installed

        :noop
      end

      def self.initial(local:, upstream:)
        return :write_upstream unless local
        return :adopt if local == upstream

        :conflict
      end
      private_class_method :initial

      def self.removal(installed:, local:)
        return :removed unless installed && local
        return :delete_upstream if local == installed

        :conflict
      end
      private_class_method :removal
    end
  end
end
