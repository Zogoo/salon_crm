class AuditLogsQuery < ApplicationQuery
  # `time_zone` is the salon's: a date filter means a business day there, not a
  # UTC day that starts at 7pm Central the evening before.
  def initialize(relation = AuditLog.all, action: nil, auditable_type: nil, actor_user_id: nil,
                 from: nil, to: nil, time_zone: Time.zone)
    @relation = relation
    @action = action
    @auditable_type = auditable_type
    @actor_user_id = actor_user_id
    @from = from
    @to = to
    @tz = time_zone
  end

  def call
    scope = @relation
    # sanitize_sql_like escapes `_` and `%` with a backslash, but SQLite's LIKE
    # has no default escape character — without ESCAPE, "gift_card" or
    # "care_notes" would match nothing.
    if @action.present?
      scope = scope.where("action LIKE ? ESCAPE '\\'", "%#{ActiveRecord::Base.sanitize_sql_like(@action)}%")
    end
    scope = scope.where(auditable_type: @auditable_type) if @auditable_type.present?
    scope = scope.where(actor_user_id: @actor_user_id) if @actor_user_id.present?
    scope = scope.where(occurred_at: @tz.parse(@from).beginning_of_day..) if @from.present?
    scope = scope.where(occurred_at: ..@tz.parse(@to).end_of_day) if @to.present?
    scope.order(occurred_at: :desc, id: :desc)
  end
end
