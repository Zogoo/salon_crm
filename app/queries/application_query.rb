# Base class for query objects. Wraps an ActiveRecord relation and returns a
# refined relation from `call`. Keeps read-side query logic out of controllers
# and models.
class ApplicationQuery
  def initialize(relation)
    @relation = relation
  end

  def call
    @relation
  end
end
