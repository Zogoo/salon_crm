module Api
  module V1
    class OrdersController < ApplicationController
      before_action :require_booking!

      # Opens (or returns) the checkout for an appointment.
      def create
        appt = Appointment.find(order_params.require(:appointment_id))
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(appt.location_id)

        order = Sales::OpenOrder.call(appointment: appt, actor: current_user)
        render json: order_json(order), status: :created
      end

      def show
        render json: order_json(find_order)
      end

      def payments
        order = find_order
        Sales::RecordPayment.call(
          order:, method: params.require(:method),
          amount_cents: params.require(:amount_cents), actor: current_user,
          reference: params[:reference]
        )
        render json: order_json(order.reload)
      rescue Sales::RecordPayment::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def gift_card_redemptions
        order = find_order
        GiftCards::RedeemCard.call(
          code: params.require(:code), order:,
          amount_cents: params.require(:amount_cents), actor: current_user
        )
        render json: order_json(order.reload)
      rescue GiftCards::RedeemCard::Invalid => e
        code, available = e.message.split(":")
        render json: { error: { code:, details: { available_cents: available&.to_i } } },
               status: :unprocessable_content
      end

      def membership_credit
        order = find_order
        membership = order.client&.membership
        return render json: { error: { code: "no_membership" } }, status: :unprocessable_content unless membership

        approver = params[:cross_location_override] ? current_user : nil
        credited = Memberships::RedeemCredit.call(
          membership:, order:, actor: current_user, cross_location_approver: approver
        )
        render json: order_json(order.reload).merge(credited_cents: credited)
      rescue Memberships::RedeemCredit::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def tips
        order = find_order
        Sales::AllocateTips.call(
          order:, amount_cents: params.require(:amount_cents),
          allocations: params[:allocations]&.map { |a| a.permit(:staff_profile_id, :amount_cents).to_h.symbolize_keys },
          actor: current_user
        )
        render json: order_json(order.reload)
      rescue Sales::AllocateTips::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      # BR-23: payments are immutable; voiding is the sanctioned correction and
      # is the Owner's alone.
      def void_payment
        require_owner!
        payment = Payment.joins(:order)
                         .where(orders: { location_id: current_user.accessible_location_ids })
                         .find(params[:payment_id])
        Sales::VoidPayment.call(payment:, actor: current_user, reason: params.require(:reason))
        render json: order_json(payment.order.reload)
      rescue Sales::VoidPayment::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def settle
        order = find_order
        Sales::SettleOrder.call(order:, actor: current_user)
        Earnings::GenerateForTip.call(order: order.reload)
        render json: order_json(order.reload)
      rescue Sales::SettleOrder::Unsettled => e
        render json: { error: { code: "unsettled", message: e.message } },
               status: :unprocessable_content
      end

      private

      def order_params = params.require(:order).permit(:appointment_id)

      def find_order
        order = Order.includes(:order_line_items, :payments, :tip_allocations,
                               :order_discounts, :gift_card_transactions).find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(order.location_id)
        order
      end

      def order_json(order)
        {
          id: order.id, number: order.number, status: order.status, kind: order.kind,
          subtotal_cents: order.subtotal_cents, discount_cents: order.discount_cents,
          tip_cents: order.tip_cents, total_cents: order.total_cents,
          paid_cents: order.paid_cents, redeemed_cents: order.redeemed_cents,
          credited_cents: order.credited_cents, outstanding_cents: order.outstanding_cents,
          appointment_id: order.appointment_id,
          client: order.client && { id: order.client_id, full_name: order.client.full_name },
          line_items: order.order_line_items.map { |li|
            { id: li.id, description: li.description, quantity: li.quantity,
              line_total_cents: li.line_total_cents, revenue_category: li.revenue_category }
          },
          payments: order.payments.map { |p|
            { id: p.id, method: p.method, amount_cents: p.amount_cents,
              status: p.status, reference: p.reference }
          },
          discounts: order.order_discounts.map { |d|
            { id: d.id, kind: d.kind, amount_cents: d.amount_cents, reason: d.reason }
          },
          gift_card_redemptions: order.gift_card_transactions.where(kind: "redeem").map { |t|
            { code: t.gift_card.code, amount_cents: t.amount_cents.abs }
          },
          tips: order.tip_allocations.map { |t|
            { staff_profile_id: t.staff_profile_id, amount_cents: t.amount_cents,
              display_name: t.staff_profile.display_name }
          }
        }
      end
    end
  end
end
