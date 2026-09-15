# The client directory's filters. Built for thousands of records: every filter
# is a WHERE clause the database answers, never a Ruby loop over all clients.
class ClientsQuery < ApplicationQuery
  # Visit dates are derived from completed appointments rather than a stored
  # column, so they can never drift from what actually happened.
  LAST_VISIT_SQL = "(SELECT MAX(a.starts_at) FROM appointments a " \
                   "WHERE a.client_id = clients.id AND a.status = 'completed')".freeze

  LAPSED_AFTER = 90.days

  def initialize(relation = Client.kept, q: nil, no_shows: nil, membership: nil, visited: nil,
                 location_id: nil)
    @relation = relation
    @q = q
    @no_shows = no_shows
    @membership = membership
    @visited = visited
    @location_id = location_id
  end

  def call
    scope = @relation.search(@q)
    scope = scope.where("clients.no_show_count > 0") if @no_shows == "true"
    scope = membership(scope)
    scope = visited(scope)
    scope = scope.where(preferred_location_id: @location_id) if @location_id.present?
    scope
  end

  private

  def membership(scope)
    members = Membership.active.select(:client_id)
    case @membership
    when "member" then scope.where(id: members)
    when "not_member" then scope.where.not(id: members)
    else scope
    end
  end

  def visited(scope)
    case @visited
    when "recent" then scope.where("#{LAST_VISIT_SQL} >= ?", LAPSED_AFTER.ago)
    when "lapsed" then scope.where("#{LAST_VISIT_SQL} < ?", LAPSED_AFTER.ago)
    when "never" then scope.where("#{LAST_VISIT_SQL} IS NULL")
    else scope
    end
  end
end
