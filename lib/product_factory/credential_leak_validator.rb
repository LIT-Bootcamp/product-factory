# frozen_string_literal: true

module ProductFactory
  class CredentialLeakValidator
    def self.call(config:, installation:)
      credential_values = config.qa.fetch("credential_env", {}).values
                                .grep(String)
                                .filter_map { |name| ENV.fetch(name, nil) }
                                .reject(&:empty?)
      stored_values = strings_in([config.to_h, installation.to_h])
      return unless credential_values.any? { |credential| stored_values.any? { |value| value.include?(credential) } }

      raise ValidationError, "credential value is stored in factory state"
    end

    def self.strings_in(value)
      case value
      when Hash then value.flat_map { |key, item| strings_in(key) + strings_in(item) }
      when Array then value.flat_map { |item| strings_in(item) }
      when String then [value]
      else []
      end
    end
    private_class_method :strings_in
  end
end
