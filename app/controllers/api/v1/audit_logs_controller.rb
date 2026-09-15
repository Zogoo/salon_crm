module Api
  module V1
    class AuditLogsController < ApplicationController
      include Pagy::Method

      before_action :require_owner!

      def index
        scope = AuditLogsQuery.new(
          AuditLog.includes(:actor_user),
          action: params[:audit_action], auditable_type: params[:auditable_type],
          actor_user_id: params[:actor_user_id], from: params[:from], to: params[:to],
          time_zone: salon_zone
        ).call
        pagy, logs = pagy(scope, limit: [ params.fetch(:limit, 50).to_i, 200 ].min)
        render json: { audit_logs: logs.map { |log| audit_log_json(log) }, meta: pagy.data_hash }
      end

      private

      # All four salons share one zone; read the log against it, like every
      # other screen (doc 03 §5).
      def salon_zone
        Location.find_by(id: current_user.accessible_location_ids.first)&.tz || Time.zone
      end

      def audit_log_json(log)
        {
          id: log.id, action: log.action,
          auditable_type: log.auditable_type, auditable_id: log.auditable_id,
          actor: log.actor_user && { id: log.actor_user_id, name: log.actor_user.name,
                                     email: log.actor_user.email, role: log.actor_role },
          changes: log.changes_json || {}, ip_address: log.ip_address,
          occurred_at: log.occurred_at.in_time_zone(salon_zone).iso8601
        }
      end
    end
  end
end
