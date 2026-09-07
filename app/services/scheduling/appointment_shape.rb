module Scheduling
  # Turns a set of requested variants into the shape the engine needs:
  # total duration, therapist count, room capacity, and the services a
  # therapist must be qualified for.
  #
  # Enhancements (essential oil, hot stone) carry price but no time and no pay,
  # so they never touch duration or the room interval.
  class AppointmentShape < ApplicationService
    attr_reader :variants, :duration_minutes, :therapist_count,
                :required_client_capacity, :requires_room_type, :service_ids

    def initialize(variants:)
      @variants = Array(variants)
      raise ArgumentError, "at least one service is required" if @variants.empty?

      payable = @variants.select(&:payable?)
      raise ArgumentError, "at least one timed service is required" if payable.empty?

      @duration_minutes = payable.sum(&:duration_minutes)
      @therapist_count  = payable.map(&:therapist_count).max
      @required_client_capacity = payable.map(&:required_client_capacity).max
      @requires_room_type = payable.map(&:requires_room_type).compact.first
      @service_ids = payable.map(&:service_id).uniq
    end

    def call = self

    # A pseudo-variant so Room.suitable_for can match the whole appointment
    # rather than one line of it.
    def room_requirement
      ServiceVariant.new(required_client_capacity:, requires_room_type:)
    end
  end
end
