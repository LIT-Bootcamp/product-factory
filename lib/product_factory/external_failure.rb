# frozen_string_literal: true

module ProductFactory
  class ExternalFailure < Error
    FIELDS = %i[failed_rule responsible_component root_cause impact recovery_action].freeze

    attr_reader(*FIELDS)

    def initialize(**details)
      FIELDS.each { |field| instance_variable_set("@#{field}", details.fetch(field)) }
      super(root_cause)
    end

    def to_h = FIELDS.to_h { |field| [field, public_send(field)] }
  end
end
