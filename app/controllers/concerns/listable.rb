# The one list contract every large collection follows, so a screen with 2,000
# clients and one with 500 gift cards page, search and sort the same way:
#
#   GET /api/v1/<resource>?q=…&page=2&limit=25&sort=name&dir=desc&<filters>
#   => { <resource>: [...], meta: { count:, page:, pages:, limit:, sort:, dir: } }
#
# `limit` is capped so no client can ask the server for everything at once, and
# `sort` only ever picks from a whitelist — never a raw column name from the
# request.
module Listable
  extend ActiveSupport::Concern
  include Pagy::Method

  MAX_LIMIT = 100
  DEFAULT_LIMIT = 25

  # What a sort whitelist may contain. Deliberately not String (and so not
  # Arel.sql): ordering is built from Arel nodes only, never by splicing text
  # into SQL, so no future whitelist entry can become an injection point.
  SORTABLE = [ Symbol, Arel::Attributes::Attribute, Arel::Nodes::NodeExpression ].freeze

  private

  def list_limit(default = DEFAULT_LIMIT)
    params.fetch(:limit, default).to_i.clamp(1, MAX_LIMIT)
  end

  def list_dir = @list_dir || (params[:dir].to_s == "desc" ? "desc" : "asc")

  # `allowed` maps a public sort key to a column symbol, an Arel attribute or
  # expression, or an array of them. Empty values sort last in both directions,
  # and the id tiebreak keeps pages stable, so a row never appears on two pages
  # or on neither.
  def list_sort(scope, allowed, default:, default_dir: "asc")
    key = allowed.key?(params[:sort].to_s) ? params[:sort].to_s : default
    @list_sort_key = key
    @list_dir = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : default_dir

    table = scope.arel_table
    direction = list_dir == "desc" ? :desc : :asc
    columns = allowed.fetch(key)
    # Not Array(): an Arel attribute is a Struct, and Array() would unpack it
    # into its table and name instead of wrapping it.
    columns = [ columns ] unless columns.is_a?(Array)
    orderings = columns.map do |column|
      sort_expression(table, column).public_send(direction).nulls_last
    end
    scope.order(*orderings, table[:id].public_send(direction))
  end

  def sort_expression(table, column)
    unless SORTABLE.any? { |type| column.is_a?(type) }
      raise ArgumentError, "sort columns must be symbols or Arel nodes, not #{column.class}"
    end

    column.is_a?(Symbol) ? table[column] : column
  end

  # A page past the end (a filter just narrowed the results) lands on the last
  # page instead of an error, so the screen always has something to show.
  def list_page(scope)
    count = scope.count
    pages = [ (count.to_f / list_limit).ceil, 1 ].max
    page = params.fetch(:page, 1).to_i.clamp(1, pages)
    pagy(scope, limit: list_limit, page:, count:)
  end

  def list_meta(pagy)
    pagy.data_hash.merge(sort: @list_sort_key, dir: list_dir)
  end
end
