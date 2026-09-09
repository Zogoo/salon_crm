module Api
  module V1
    # BR-36: managers are paid a flat monthly amount and never appear in
    # earning_lines. This is the payroll view for that, kept separate from
    # therapist earnings so the two can never be added together by accident.
    class ManagerPayoutsController < ApplicationController
      before_action :require_owner!

      def index
        month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.current.beginning_of_month
        payouts = ManagerPayout.includes(staff_profile: :location).where(month:).order(:id)

        render json: {
          month: month.strftime("%Y-%m"),
          total_cents: payouts.sum(:amount_cents),
          payouts: payouts.map { |p|
            { id: p.id, staff_profile_id: p.staff_profile_id,
              display_name: p.staff_profile.display_name,
              location: p.staff_profile.location.name,
              amount_cents: p.amount_cents, status: p.status, paid_at: local_iso(p.paid_at, p.staff_profile.location) }
          }
        }
      end
    end
  end
end
