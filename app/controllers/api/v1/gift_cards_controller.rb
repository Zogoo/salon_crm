module Api
  module V1
    class GiftCardsController < ApplicationController
      include Listable
      # BR-31: Owner and Manager only. Staff cannot view or sell gift cards.
      before_action :require_booking!
      before_action :require_owner!, only: %i[adjust void]

      GC_SORTS = {
        "sold" => :sold_at, "code" => :code,
        "balance" => :current_balance_cents, "expires" => :expires_at
      }.freeze

      def index
        scope = GiftCard.includes(:sold_at_location, :buyer_client)
                        .where(sold_at_location_id: current_user.accessible_location_ids)
        scope = scope.where(sold_at_location_id: params[:location_id]) if params[:location_id].present?
        scope =
          case params[:status]
          when "active", "depleted", "void" then scope.where(status: params[:status])
          # BR-30: past its date but still holding the client's money.
          when "expired" then scope.where(expires_at: ...Time.current).where("current_balance_cents > 0")
          else scope
          end
        query = params[:q].presence || params[:search]
        if query.present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
          scope = scope.where("code LIKE :upper OR LOWER(buyer_name) LIKE :lower OR buyer_phone LIKE :term " \
                              "OR LOWER(recipient_name) LIKE :lower",
                              upper: term.upcase, lower: term.downcase, term:)
        end
        scope = list_sort(scope, GC_SORTS, default: "sold", default_dir: "desc")
        pagy, cards = list_page(scope)
        render json: { gift_cards: cards.map { |c| card_json(c) }, meta: list_meta(pagy) }
      end

      # Barcode scan and manual lookup are the same call (FRS §12).
      def show
        card = GiftCard.includes(:gift_card_transactions).find_by!(code: params[:id].to_s.upcase)
        render json: card_json(card, ledger: true)
      end

      def create
        location = scoped_location!(card_params.require(:location_id))
        card = GiftCards::IssueCard.call(
          location:, amount_cents: card_params.require(:amount_cents),
          payment_method: card_params.require(:payment_method), actor: current_user,
          code: card_params[:code],
          buyer_client: buyer_client,
          buyer_name: card_params[:buyer_name], buyer_phone: card_params[:buyer_phone],
          recipient_client: Client.find_by(id: card_params[:recipient_client_id]),
          recipient_name: card_params[:recipient_name],
          recipient_phone: card_params[:recipient_phone]
        )
        render json: card_json(card, ledger: true), status: :created
      rescue GiftCards::IssueCard::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      NegativeBalance = Class.new(StandardError)

      def adjust
        amount = params.require(:amount_cents).to_i

        card = ImmediateTransaction.call do
          # Read the balance under the write lock, not before it. Two
          # adjustments racing each other would otherwise both compute from the
          # same starting figure, and one would be silently lost.
          locked = GiftCard.lock.find(params[:id])
          balance = locked.current_balance_cents + amount
          raise NegativeBalance if balance.negative?

          GiftCardTransaction.create!(
            gift_card: locked, kind: "adjust", amount_cents: amount,
            balance_after_cents: balance, performed_by_user: current_user,
            occurred_at: Time.current, note: params[:reason]
          )
          locked.update!(current_balance_cents: balance,
                         status: balance.zero? ? "depleted" : "active")
          AuditLog.record!(auditable: locked, action: "gift_card.adjusted", actor: current_user,
                           changes: { amount_cents: amount, reason: params[:reason] })
          locked
        end

        render json: card_json(card, ledger: true)
      rescue NegativeBalance
        render json: { error: { code: "negative_balance" } }, status: :unprocessable_content
      end

      def void
        card = GiftCard.find(params[:id])
        card.update!(status: "void")
        AuditLog.record!(auditable: card, action: "gift_card.voided", actor: current_user)
        render json: card_json(card)
      end

      # A scanner types the code into the same lookup; there is no separate
      # barcode column, so the code on the card *is* the barcode.
      def scan
        card = GiftCard.includes(:gift_card_transactions).find_by!(code: normalised(params[:barcode]))
        render json: card_json(card, ledger: true)
      end

      # BR-27: a card is company-wide, so it redeems against any location's
      # order. Same service as the checkout path — one redemption rule.
      def redeem
        order = Order.find(params.require(:order_id))
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(order.location_id)

        GiftCards::RedeemCard.call(
          code: normalised(params[:id]), order:,
          amount_cents: params.require(:amount_cents), actor: current_user
        )
        render json: card_json(GiftCard.find_by!(code: normalised(params[:id])), ledger: true)
      rescue GiftCards::RedeemCard::Invalid => e
        code, available = e.message.split(":")
        render json: { error: { code:, details: { available_cents: available&.to_i } } },
               status: :unprocessable_content
      end

      private

      # Client records are company-wide; only an explicit, live client links a sale.
      def buyer_client
        Client.kept.find(card_params[:buyer_client_id]) if card_params[:buyer_client_id].present?
      end

      def normalised(value) = value.to_s.strip.upcase

      def card_params
        params.require(:gift_card).permit(:location_id, :amount_cents, :payment_method, :code,
                                          :buyer_client_id, :buyer_name, :buyer_phone,
                                          :recipient_client_id, :recipient_name, :recipient_phone)
      end

      def card_json(card, ledger: false)
        json = {
          id: card.id, code: card.code, status: card.status,
          initial_value_cents: card.initial_value_cents,
          current_balance_cents: card.current_balance_cents,
          redeemable: card.redeemable?,
          # BR-30: expiry is a flag, not a forfeiture. Say so, so the front desk
          # never tells a client their money is gone.
          expired: card.expired?,
          expires_at: local_iso(card.expires_at, card.sold_at_location),
          sold_at: local_iso(card.sold_at, card.sold_at_location),
          sold_at_location: { id: card.sold_at_location_id, name: card.sold_at_location.name },
          buyer: { client_id: card.buyer_client_id, name: card.buyer_name, phone: card.buyer_phone },
          recipient: { client_id: card.recipient_client_id, name: card.recipient_name }
        }
        if ledger
          json[:ledger] = card.gift_card_transactions.order(:occurred_at).map { |t|
            { kind: t.kind, amount_cents: t.amount_cents, balance_after_cents: t.balance_after_cents,
              occurred_at: local_iso(t.occurred_at, t.location || card.sold_at_location),
              location_id: t.location_id, note: t.note }
          }
        end
        json
      end
    end
  end
end
