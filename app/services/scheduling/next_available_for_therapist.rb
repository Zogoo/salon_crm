module Scheduling
  # FRS §5 / BR-16: when the requested therapist is unavailable, offer that
  # same therapist's next times. It never suggests a different therapist.
  class NextAvailableForTherapist < ApplicationService
    def initialize(location:, variants:, staff_profile_id:, after:, limit: 3, horizon_days: 14)
      @location = location
      @variants = variants
      @staff_id = staff_profile_id
      @after = after
      @limit = limit
      @horizon = horizon_days
    end

    def call
      from = @after.to_date
      AvailabilitySearch.call(
        location: @location, variants: @variants,
        date_from: from, date_to: from + @horizon,
        requested_staff_profile_id: @staff_id
      ).flat_map { |d| d[:slots] }
       .select { |s| s.start_at > @after }
       .first(@limit)
    end
  end
end
