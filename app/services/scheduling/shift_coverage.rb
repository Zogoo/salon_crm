module Scheduling
  # BR-07 / doc 03 §4.7: availability is never removed out from under a booked
  # appointment. Shortening a shift, deleting one, dropping a break onto it, or
  # applying an approved shift-change request are all the same question —
  # "which appointments would this leave uncovered?" — so they ask it here.
  #
  # Returns the appointments that would be orphaned. Empty means safe.
  module ShiftCoverage
    module_function

    # Appointments inside the shift's current span that the proposed span would
    # no longer fully cover.
    def orphaned_by_change(shift, starts_at:, ends_at:)
      inside(shift.staff_profile_id, shift.starts_at, shift.ends_at)
        .reject { |row| row.starts_at >= starts_at && row.ends_at <= ends_at }
    end

    # Everything the window covers — used when the availability disappears
    # entirely (a deleted shift) or is punched out (a break).
    def inside(staff_profile_id, from, to)
      AppointmentStaff.active
                      .where(staff_profile_id:)
                      .overlapping(from, to)
                      .to_a
    end

    def appointment_ids(rows) = rows.map(&:appointment_id).uniq
  end
end
