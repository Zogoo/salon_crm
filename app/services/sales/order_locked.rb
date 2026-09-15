module Sales
  # Raised when an appointment change would re-price an order that money has
  # already been taken against. Controllers turn it into a 422 with the code.
  OrderLocked = Class.new(StandardError)
end
