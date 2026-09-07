module Api
  module V1
    class ApprovalRequestsController < ApplicationController
      before_action :require_booking!

      def index
        scope = ApprovalRequest.pending
                               .joins(:appointment)
                               .where(appointments: { location_id: current_user.accessible_location_ids })
                               .includes(:requested_staff_profile, appointment: %i[client location])
        render json: { approval_requests: scope.order(:created_at).map { |r| request_json(r) } }
      end

      def approve = decide(:approve)
      def reject  = decide(:reject)

      private

      def decide(decision)
        request = ApprovalRequest.joins(:appointment)
                                 .where(appointments: { location_id: current_user.accessible_location_ids })
                                 .find(params[:id])
        Scheduling::ApproveTherapistRequest.call(
          request:, actor: current_user, decision:, note: params[:note]
        )
        render json: request_json(request.reload)
      end

      def request_json(req)
        appt = req.appointment
        {
          id: req.id, status: req.status,
          pending_for_minutes: req.pending_for_minutes,
          auto_approves_at: req.auto_approves_at.iso8601,
          past_review_target: req.past_review_target?,
          requested_therapist: { id: req.requested_staff_profile_id,
                                 display_name: req.requested_staff_profile.display_name },
          appointment: { id: appt.id, reference: appt.reference,
                         starts_at: local_iso(appt.starts_at, appt.location),
                         status: appt.status,
                         client_name: appt.client.full_name,
                         location: appt.location.name }
        }
      end
    end
  end
end
