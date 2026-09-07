class NotesQuery < ApplicationQuery
  def call(search: nil)
    scope = @relation.recent
    scope = filter_by_search(scope, search) if search.present?
    scope
  end

  private

  def filter_by_search(scope, term)
    pattern = "%#{sanitize_like(term)}%"
    scope.where("title LIKE :q ESCAPE '\\' OR body LIKE :q ESCAPE '\\'", q: pattern)
  end

  def sanitize_like(value)
    value.gsub(/[%_\\]/) { |m| "\\#{m}" }
  end
end
