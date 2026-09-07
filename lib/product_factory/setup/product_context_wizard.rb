# frozen_string_literal: true

module ProductFactory
  module Setup
    class ProductContextWizard < Service
      FIELDS = [
        ["mission", "Mission", :required],
        ["target_users", "Target users", :required],
        ["primary_user_problem", "Primary user problem", :required],
        ["desired_outcome", "Desired outcome", :required],
        ["markets_and_languages", "Markets and languages", :required],
        ["competitor_seeds", "Competitor seeds", :optional],
        ["constraints", "Constraints", :optional],
        ["non_goals", "Non-goals", :optional]
      ].freeze

      def initialize(input:, output:, snapshot:, document_ids:)
        super()
        @input = input
        @output = output
        @snapshot = snapshot
        @document_ids = document_ids
      end

      def call
        return if @snapshot.fetch("documents", {}).key?(@document_ids.last)

        FIELDS.to_h do |key, prompt, required|
          [key, required == :required ? required_answer(prompt) : optional_answer(prompt)]
        end
      end

      private

      def required_answer(prompt)
        loop do
          @output.print("#{prompt}: ")
          answer = @input.gets
          raise UsageError, "#{prompt} is required" unless answer

          answer = answer.chomp.strip
          return answer unless answer.empty?
        end
      end

      def optional_answer(prompt)
        @output.print("#{prompt}: ")
        @input.gets.to_s.chomp.strip
      end
    end
  end
end
