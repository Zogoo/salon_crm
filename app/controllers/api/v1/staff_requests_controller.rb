module Api
  module V1
    class StaffRequestsController < ApplicationController
      def index
        scope = StaffRequest.includes(:staff_profile, :shift)
        scope =
          case current_user.role
          when "owner"   then scope
          when "manager" then scope.joins(:staff_profile)
                                   .where(staff_profiles: { location_id: current_user.location_id })
          else scope.where(staff_profile_id: current_user.staff_profile&.id)
          end
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        render json: { staff_requests: scope.order(created_at: :desc).map { |r| request_json(r) } }
      end

      # BR-05: only staff raise requests — that is the point of the workflow.
      def create
        profile = current_user.staff_profile
        raise Authorizable::Forbidden unless profile

        problem = request_problem(profile)
        return render_invalid(problem, code: problem) if problem

        request = StaffRequest.create!(
          staff_profile: profile, kind: request_params.require(:kind),
          shift_id: request_params[:shift_id],
          requested_payload: request_params[:requested_payload]&.to_unsafe_h || {},
          note: request_params[:note], status: "submitted"
        )
        render json: request_json(request), status: :created
      end

      def approve = decide(:approve)
      def reject  = decide(:reject)

      def withdraw
        request = StaffRequest.find(params[:id])
        raise ActiveRecord::RecordNotFound unless request.staff_profile_id == current_user.staff_profile&.id
        request.update!(status: "withdrawn")
        render json: request_json(request)
      end

      private

      def request_params
        params.require(:staff_request).permit(:kind, :shift_id, :note, requested_payload: {})
      end

      # A request must point at something the reviewer can act on: one of the
      # requester's own shifts, or a real location other than their own.
      def request_problem(profile)
        payload = request_params[:requested_payload]&.to_unsafe_h || {}
        case request_params[:kind]
        when "shift_change"
          "shift_required" unless Shift.exists?(id: request_params[:shift_id], staff_profile_id: profile.id)
        when "location_change"
          location_id = payload["location_id"].to_i
          "location_required" if location_id == profile.location_id || !Location.active.exists?(id: location_id)
        end
      end

      def decide(decision)
        request = StaffRequest.find(params[:id])
        # The reviewer's note comes back as `review_note`, so accept that name
        # as well as `note` — `note` alone reads as the requester's own note.
        Workforce::ApproveStaffRequest.call(request:, actor: current_user, decision:,
                                            note: params[:review_note] || params[:note])
        render json: request_json(request.reload)
      rescue Workforce::ApproveStaffRequest::Forbidden => e
        # A distinct code, because the console shows a specific message for the
        # Owner-only rule rather than a generic refusal.
        render json: { error: { code: e.message.presence || "forbidden" } }, status: :forbidden
      rescue Workforce::ApproveStaffRequest::Invalid => e
        code, ids = e.message.split(":")
        render json: { error: { code:, details: { appointment_ids: ids&.split(",")&.map(&:to_i) } } },
               status: :unprocessable_content
      end

      def request_json(r)
        {
          id: r.id, kind: r.kind, status: r.status,
          staff_profile_id: r.staff_profile_id,
          display_name: r.staff_profile.display_name,
          shift_id: r.shift_id,
          # Enough to read the request without looking anything up.
          shift: r.shift && {
            work_date: r.shift.work_date,
            starts_at: r.shift.starts_at.in_time_zone(r.shift.location.tz).strftime("%H:%M"),
            ends_at: r.shift.ends_at.in_time_zone(r.shift.location.tz).strftime("%H:%M")
          },
          requested_location: Location.find_by(id: r.requested_payload["location_id"])&.then { |l|
            { id: l.id, name: l.name }
          },
          requested_payload: r.requested_payload,
          note: r.note, review_note: r.review_note,
          reviewed_by_role: r.reviewer_role,
          created_at: local_iso(r.created_at, r.staff_profile.location)
        }
      end
    end
  end
end
