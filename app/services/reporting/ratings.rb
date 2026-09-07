module Reporting
  # FRS §11.2 — average and distribution per therapist, plus the recommend rate.
  class Ratings < ApplicationService
    def initialize(location_ids:, from:, to:)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
    end

    def call
      ratings = AppointmentRating
                  .joins(:appointment)
                  .where(appointments: { location_id: @location_ids })
                  .where(submitted_at: @from.beginning_of_day..@to.end_of_day)
                  .includes(:staff_profile)

      {
        from: @from, to: @to, count: ratings.size,
        average: ratings.any? ? (ratings.sum(&:score).to_f / ratings.size).round(2) : nil,
        distribution: (1..10).index_with { |n| ratings.count { |r| r.score == n } },
        recommend_rate: recommend_rate(ratings),
        by_therapist: ratings.group_by(&:staff_profile).map { |staff, rs|
          { staff_profile_id: staff.id, display_name: staff.display_name,
            count: rs.size, average: (rs.sum(&:score).to_f / rs.size).round(2) }
        }.sort_by { |r| -r[:count] }
      }
    end

    private

    def recommend_rate(ratings)
      answered = ratings.reject { |r| r.would_recommend.nil? }
      return nil if answered.empty?
      (answered.count(&:would_recommend).to_f / answered.size * 100).round(1)
    end
  end
end
