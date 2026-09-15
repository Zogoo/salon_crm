module Api
  module V1
    module Clients
      # FRS §12 / BR-42: the client profile is company-wide, so every read here
      # spans all four locations rather than the current one.
      class HistoryController < ApplicationController
        include Listable

        before_action :set_client

        def appointments
          scope = @client.appointments.includes(:location, :room, :staff_profiles)
                         .order(starts_at: :desc)
          # Staff see only the appointments they worked (doc 05 §"Clients").
          if current_user.staff?
            scope = scope.joins(:appointment_staff)
                         .where(appointment_staff: { staff_profile_id: current_user.staff_profile&.id })
          end

          pagy, records = list_page(scope)
          render json: { appointments: records.map { |a| appointment_json(a) }, meta: pagy.data_hash }
        end

        def orders
          require_role!(:owner, :manager)
          scope = @client.orders.includes(:location, :payments).order(created_at: :desc)
          pagy, records = list_page(scope)
          render json: { orders: records.map { |o| order_json(o) }, meta: pagy.data_hash }
        end

        def gift_cards
          require_role!(:owner, :manager)
          cards = GiftCard.where(buyer_client_id: @client.id)
                          .includes(:sold_at_location).order(created_at: :desc)
          render json: { gift_cards: cards.map { |c| gift_card_json(c) } }
        end

        def ratings
          require_role!(:owner, :manager)
          scope = AppointmentRating.joins(:appointment)
                                   .where(appointments: { client_id: @client.id })
                                   .includes(:staff_profile, appointment: :location)
                                   .order(created_at: :desc)
          render json: { ratings: scope.map { |r| rating_json(r) } }
        end

        # BR-46: what the front desk wants on screen when the phone rings.
        def summary
          require_role!(:owner, :manager)
          render json: Crm::ClientHistorySummary.call(client: @client)
        end

        private

        def set_client = @client = Client.kept.find(params[:client_id])

        def appointment_json(appt)
          { id: appt.id, reference: appt.reference, status: appt.status,
            location: appt.location.name,
            starts_at: local_iso(appt.starts_at, appt.location),
            therapists: appt.staff_profiles.map(&:display_name),
            total_price_cents: appt.total_price_cents }
        end

        def order_json(order)
          { id: order.id, number: order.number, status: order.status,
            location: order.location.name, total_cents: order.total_cents,
            paid_cents: order.payments.captured.sum(:amount_cents),
            created_at: local_iso(order.created_at, order.location) }
        end

        def gift_card_json(card)
          { id: card.id, code: card.code, balance_cents: card.current_balance_cents,
            initial_value_cents: card.initial_value_cents,
            status: card.status, sold_at: local_iso(card.sold_at, card.sold_at_location),
            sold_at_location: card.sold_at_location&.name }
        end

        def rating_json(rating)
          { id: rating.id, appointment_id: rating.appointment_id, score: rating.score, comment: rating.feedback,
            therapist: rating.staff_profile&.display_name,
            created_at: local_iso(rating.created_at, rating.appointment.location) }
        end
      end
    end
  end
end
