module Reporting
  # BR-28 fixes the denominators, because utilisation without them means
  # nothing:
  #
  #   therapist = booked minutes ÷ published shift minutes
  #   room      = booked minutes ÷ the location's open minutes for that room
  #
  # Booked minutes are the *service*, excluding the 15-minute buffer — the
  # buffer is reserved time, not sold time, and counting it would flatter every
  # figure by 20%.
  class Utilization < ApplicationService
    def initialize(location:, from:, to:)
      @location = location
      @from = from.to_date
      @to = to.to_date
    end

    def call
      appts = Appointment.where(location_id: @location.id, status: "completed")
                         .where(starts_at: window)
                         .includes(:room, :staff_profiles)

      {
        from: @from, to: @to,
        open_minutes_per_room: open_minutes,
        rooms: room_rows(appts),
        therapists: therapist_rows(appts)
      }
    end

    private

    def window
      tz = @location.tz
      tz.local(@from.year, @from.month, @from.day).beginning_of_day..
        tz.local(@to.year, @to.month, @to.day).end_of_day
    end

    def days = (@to - @from).to_i + 1

    def open_minutes
      minutes = (@location.closes_at - @location.opens_at) / 60
      (minutes * days).round
    end

    def service_minutes(appt) = ((appt.service_ends_at - appt.starts_at) / 60).round

    def room_rows(appts)
      by_room = appts.group_by(&:room)
      @location.rooms.active.order(:position).map do |room|
        booked = (by_room[room] || []).sum { |a| service_minutes(a) }
        { room_id: room.id, name: room.name, booked_minutes: booked,
          available_minutes: open_minutes,
          utilization_percent: percent(booked, open_minutes) }
      end
    end

    def therapist_rows(appts)
      booked = Hash.new(0)
      appts.each { |a| a.staff_profiles.each { |sp| booked[sp.id] += service_minutes(a) } }

      shift_minutes = Shift.published
                           .where(location_id: @location.id, work_date: @from..@to)
                           .group(:staff_profile_id)
                           .sum("(julianday(ends_at) - julianday(starts_at)) * 24 * 60")

      StaffProfile.active.where(location_id: @location.id).order(:display_name).map do |sp|
        available = shift_minutes[sp.id].to_f.round
        { staff_profile_id: sp.id, display_name: sp.display_name,
          booked_minutes: booked[sp.id], available_minutes: available,
          utilization_percent: percent(booked[sp.id], available) }
      end
    end

    def percent(part, whole) = whole.to_i.zero? ? 0.0 : (part.to_f / whole * 100).round(1)
  end
end
