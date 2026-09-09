module Api
  module V1
    class ReportsController < ApplicationController
      before_action :require_owner!,
                    only: %i[daily_revenue gift_card_liability ratings
                             no_shows utilization client_retention membership]

      # FRS §10
      def daily_revenue
        from, to = range
        ids = location_ids
        data = Reporting::DailyRevenue.call(location_ids: ids, from:, to:)
        respond_with_format(data, csv_rows: revenue_csv(data), filename: "revenue-#{from}-#{to}")
      end

      # FRS §9
      def client_log
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : location.today
        rows = Reporting::ClientLog.call(location:, date:)
        respond_with_format({ date:, rows: }, csv_rows: client_log_csv(rows),
                            filename: "client-log-#{date}")
      end

      def gift_card_liability
        data = Reporting::GiftCardLiability.call(location_ids: location_ids)
        # Every timestamp we hand out carries the salon's offset; `as_of` is an
        # instant like any other, and the client reads the wall clock straight
        # off the string.
        render json: data.merge(as_of: local_iso(data[:as_of], reporting_location))
      end

      # FRS §23 — Owner only, like every other money report.
      def membership
        from, to = range
        render json: Reporting::Membership.call(location_ids:, from:, to:)
      end

      # BR-45a: the ratings a Manager is allowed to see, because they are the
      # ones they are expected to act on at their own location.
      def rating_alerts
        from, to = range
        scope = AppointmentRating.joins(appointment: :location)
                                 .where(appointments: { location_id: location_ids })
                                 .where(created_at: from.beginning_of_day..to.end_of_day)
                                 .includes(:staff_profile, appointment: :location)
                                 .order(created_at: :desc)

        alerts = scope.select { |r| r.low?(r.appointment.location.low_rating_alert_below) }

        render json: {
          from:, to:, count: alerts.size,
          alerts: alerts.map { |r|
            { id: r.id, score: r.score, feedback: r.feedback, improvement: r.improvement,
              threshold: r.appointment.location.low_rating_alert_below,
              location: r.appointment.location.name,
              therapist: r.staff_profile&.display_name,
              appointment_id: r.appointment_id,
              created_at: local_iso(r.created_at, r.appointment.location) }
          }
        }
      end

      def ratings
        from, to = range
        render json: Reporting::Ratings.call(location_ids: location_ids, from:, to:)
      end

      # FRS §21
      def no_shows
        from, to = range
        render json: Reporting::NoShows.call(location_ids:, from:, to:)
      end

      # BR-28 fixes the denominators; see the service.
      def utilization
        location = scoped_location!(params.require(:location_id))
        from, to = range
        render json: Reporting::Utilization.call(location:, from:, to:)
      end

      def client_retention
        from, to = range
        render json: Reporting::ClientRetention.call(location_ids:, from:, to:)
      end

      # BR-19 / OQ-11: fees are profile-only, so this digest is the only thing
      # standing between an unpaid fee and it being forgotten.
      def outstanding_fees
        orders = Order.outstanding_fees
                      .where(location_id: location_ids)
                      .includes(:client, :location, :order_line_items)
        render json: {
          total_cents: orders.sum(:total_cents),
          orders: orders.order(created_at: :desc).map { |o|
            { id: o.id, number: o.number, created_at: local_iso(o.created_at, o.location),
              amount_cents: o.total_cents, location: o.location.name,
              client: o.client && { id: o.client_id, full_name: o.client.full_name },
              description: o.order_line_items.first&.description }
          }
        }
      end

      private

      # Reports can span locations, but they are all in one zone; the first in
      # scope is the one whose clock the report is read against, matching how
      # `range` picks the default business day.
      def reporting_location
        Location.find_by(id: location_ids.first)
      end

      def location_ids
        requested = Array(params[:location_id] || params[:location_ids]).map(&:to_i).reject(&:zero?)
        allowed = current_user.accessible_location_ids
        requested.any? ? (requested & allowed) : allowed
      end

      def range
        # The salon's business day, not UTC's — see Location#today.
        default = Location.find_by(id: location_ids.first)&.today || Date.current
        from = params[:from].present? ? Date.parse(params[:from]) : default
        to = params[:to].present? ? Date.parse(params[:to]) : from
        [ from, to ]
      end

      # XLSX and PDF are not built (doc 08 §3); CSV covers the operational need
      # with the stdlib and no new dependency.
      def respond_with_format(json, csv_rows:, filename:)
        if params[:format] == "csv"
          send_data to_csv(csv_rows), type: "text/csv",
                    disposition: "attachment; filename=\"#{filename}.csv\""
        else
          render json: json
        end
      end

      def to_csv(rows)
        require "csv"
        CSV.generate { |csv| rows.each { |r| csv << r } }
      end

      def revenue_csv(data)
        [ [ "Method", "Cents" ] ] +
          data[:by_method].map { |m, c| [ m, c ] } +
          [ [], [ "Service revenue", data[:service_revenue_cents] ],
            [ "Gift card liability", data[:gift_card_liability_cents] ],
            [ "Membership liability", data[:membership_liability_cents] ],
            [ "Fees", data[:fees_cents] ],
            [ "Tips", data[:tips_cents] ] ]
      end

      def client_log_csv(rows)
        [ %w[Time Client Therapists Services Minutes PriceCents TipCents PaidCents Methods] ] +
          rows.map { |r|
            [ r[:time], r[:client_name], r[:therapists].join("|"), r[:services].join("|"),
              r[:duration_minutes], r[:service_price_cents], r[:tip_cents],
              r[:total_paid_cents], r[:payment_methods].join("|") ]
          }
      end
    end
  end
end
