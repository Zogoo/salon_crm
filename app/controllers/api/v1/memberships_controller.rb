module Api
  module V1
    class MembershipsController < ApplicationController
      before_action :require_booking!
      before_action :require_owner!, only: :adjust_credits

      def index
        scope = Membership.includes(:client, :location)
                          .where(location_id: current_user.accessible_location_ids)
        scope = scope.where(status: params[:status]) if params[:status].present?
        render json: { memberships: scope.order(created_at: :desc).map { |m| membership_json(m) } }
      end

      def show = render json: membership_json(find_membership, detail: true)

      def create
        client = Client.kept.find(membership_params.require(:client_id))
        location = scoped_location!(membership_params.require(:location_id))
        membership = Memberships::Enrol.call(
          client:, location:, actor: current_user,
          default_service_variant_id: membership_params[:default_service_variant_id]
        )
        render json: membership_json(membership, detail: true), status: :created
      rescue Memberships::Enrol::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def update
        membership = find_membership
        membership.update!(default_service_variant_id: membership_params[:default_service_variant_id])
        render json: membership_json(membership, detail: true)
      end

      # Release 1 billing: recording the payment is what grants the credit.
      def record_payment
        membership = find_membership
        Memberships::RecordCyclePayment.call(
          membership:, method: params.require(:method), actor: current_user
        )
        render json: membership_json(membership.reload, detail: true)
      rescue Memberships::RecordCyclePayment::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def request_cancellation
        membership = Memberships::RequestCancellation.call(
          membership: find_membership, actor: current_user
        )
        render json: membership_json(membership, detail: true)
      end

      def adjust_credits
        membership = find_membership
        amount = params.require(:amount).to_i
        balance = membership.credits_balance + amount
        if balance.negative? || balance > Membership::CREDIT_CAP
          return render json: { error: { code: "credit_cap_reached" } }, status: :unprocessable_content
        end

        ImmediateTransaction.call do
          MembershipCreditTransaction.create!(
            membership:, kind: "adjust", amount:, balance_after: balance,
            performed_by_user: current_user, occurred_at: Time.current, note: params[:reason]
          )
          membership.update!(credits_balance: balance)
          AuditLog.record!(auditable: membership, action: "membership.credits_adjusted",
                           actor: current_user, changes: { amount:, reason: params[:reason] })
        end
        render json: membership_json(membership.reload, detail: true)
      end

      private

      def membership_params
        params.require(:membership).permit(:client_id, :location_id, :default_service_variant_id)
      end

      def find_membership
        m = Membership.includes(:client, :location, :membership_credit_transactions).find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(m.location_id)
        m
      end

      def membership_json(m, detail: false)
        json = {
          id: m.id, status: m.status, price_cents: m.price_cents,
          credits_balance: m.credits_balance, credits_cap: Membership::CREDIT_CAP,
          at_cap: m.at_cap?,
          client: { id: m.client_id, full_name: m.client.full_name },
          # BR-39a: the home location, and the fact it is not portable.
          location: { id: m.location_id, name: m.location.name },
          current_period_end: m.current_period_end.iso8601,
          cancellation_effective_at: m.cancellation_effective_at&.iso8601
        }
        if detail
          json[:default_service_variant_id] = m.default_service_variant_id
          json[:cycles] = m.membership_cycles.order(period_start: :desc).limit(12).map { |c|
            { period_start: c.period_start.to_date, charged_at: c.charged_at&.to_date,
              amount_cents: c.amount_cents, credit_granted: c.credit_granted,
              forfeited_to_cap: c.forfeited_to_cap }
          }
          json[:credit_ledger] = m.membership_credit_transactions.order(:occurred_at).map { |t|
            { kind: t.kind, amount: t.amount, balance_after: t.balance_after,
              occurred_at: t.occurred_at.iso8601,
              cross_location_override: t.cross_location_approved_by_user_id.present? }
          }
        end
        json
      end
    end
  end
end
