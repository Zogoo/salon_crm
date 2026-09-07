# Base class for service objects. One public entry point: `.call`.
#
#   class DoThing < ApplicationService
#     def initialize(x:) = @x = x
#     def call = @x * 2
#   end
#
#   DoThing.call(x: 21) # => 42
class ApplicationService
  def self.call(...)
    new(...).call
  end
end
