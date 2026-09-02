module ProductFactory
  class Error < StandardError; end
  class UsageError < Error; end
  class ValidationError < Error; end
  class ConflictError < Error; end
end
