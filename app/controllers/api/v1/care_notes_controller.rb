module Api
  module V1
    class CareNotesController < ApplicationController
      # Doc 04 §5: Owner, Manager, and the therapist on that appointment.
      # Every read is audit-logged — it is the only way to answer "who looked".
      def index
        appt = find_appointment!
        AuditLog.record!(auditable: appt, action: "care_notes.read", actor: current_user)
        notes = appt.care_notes.includes(:staff_profile).order(:created_at)
        render json: { care_notes: notes.map { |n| note_json(n) } }
      end

      def create
        appt = find_appointment!
        profile = current_user.staff_profile
        raise Authorizable::Forbidden unless profile

        note = Crm::RecordCareNote.call(
          appointment: appt, staff_profile: profile, body: params.require(:body),
          supersedes: params[:supersedes_note_id] && CareNote.find(params[:supersedes_note_id])
        )
        render json: note_json(note), status: :created
      rescue Crm::RecordCareNote::Forbidden
        render json: { error: { code: "not_assigned_to_this_appointment" } }, status: :forbidden
      end

      private

      def find_appointment!
        appt = Appointment.includes(:appointment_staff).find(params.require(:appointment_id))
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(appt.location_id)
        if current_user.staff? &&
           !appt.appointment_staff.exists?(staff_profile_id: current_user.staff_profile&.id)
          raise ActiveRecord::RecordNotFound
        end
        appt
      end

      def note_json(note)
        { id: note.id, body: note.body, created_at: note.created_at.iso8601,
          author: note.staff_profile.display_name,
          supersedes_note_id: note.supersedes_note_id }
      end
    end
  end
end
