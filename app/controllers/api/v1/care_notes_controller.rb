module Api
  module V1
    class CareNotesController < ApplicationController
      # Doc 04 §5: Owner, Manager, and the therapist on that appointment.
      # Every read is audit-logged — it is the only way to answer "who looked".
      def index
        appt = find_appointment!
        AuditLog.record!(auditable: appt, action: "care_notes.read", actor: current_user)
        notes = appt.care_notes.includes(:staff_profile).order(:created_at)
        render json: { care_notes: notes.map { |n| note_json(n, appt.location) } }
      end

      def create
        appt = find_appointment!
        profile = current_user.staff_profile
        raise Authorizable::Forbidden unless profile

        note = Crm::RecordCareNote.call(
          appointment: appt, staff_profile: profile, body: params.require(:body),
          supersedes: params[:supersedes_note_id] && CareNote.find(params[:supersedes_note_id])
        )
        render json: note_json(note, appt.location), status: :created
      rescue Crm::RecordCareNote::Forbidden
        render json: { error: { code: "not_assigned_to_this_appointment" } }, status: :forbidden
      end

      # BR-44: a correction never edits the original. It is a new note that
      # points at the one it replaces, so both remain readable.
      def supersede
        original = CareNote.includes(appointment: :location).find(params[:id])
        author = current_user.staff_profile
        # Only the author corrects their own note — a second opinion is a note
        # of its own, not a correction of someone else's.
        raise ActiveRecord::RecordNotFound unless author && original.staff_profile_id == author.id

        note = CareNote.create!(appointment: original.appointment, staff_profile: author,
                                body: params.require(:body), supersedes_note: original)
        render json: note_json(note, original.appointment.location), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      private

      def find_appointment!
        appt = Appointment.includes(:appointment_staff).find(params.require(:appointment_id))
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(appt.location_id)
        # A provisional (unconfirmed) therapist is not "the therapist on that
        # appointment" for BR-44 purposes.
        if current_user.staff? &&
           (!appt.staff_assignment_confirmed? ||
            !appt.appointment_staff.exists?(staff_profile_id: current_user.staff_profile&.id))
          raise ActiveRecord::RecordNotFound
        end
        appt
      end

      def note_json(note, location)
        { id: note.id, body: note.body,
          staff_profile_id: note.staff_profile_id,
          created_at: local_iso(note.created_at, location),
          author: note.staff_profile.display_name,
          supersedes_note_id: note.supersedes_note_id }
      end
    end
  end
end
