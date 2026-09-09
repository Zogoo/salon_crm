module Api
  module V1
    class EarningsController < ApplicationController
      # BR-02: earnings are Owner-only. A therapist may see their own.
      before_action :require_owner!, except: %i[report statement]

      def periods
        render json: {
          periods: EarningPeriod.order(starts_on: :desc).limit(24).map { |p| period_json(p) }
        }
      end

      def build
        period = EarningPeriod.find(params[:id])
        Earnings::BuildStatements.call(period:)
        render json: period_json(period.reload, statements: true)
      end

      def lock
        period = EarningPeriod.find(params[:id])
        Earnings::LockPeriod.call(period:, actor: current_user)
        render json: period_json(period.reload, statements: true)
      end

      def statements
        period = EarningPeriod.find(params[:id])
        render json: period_json(period, statements: true)
      end

      def statement
        st = EarningStatement.includes(:staff_profile, :earning_adjustments).find(params[:id])
        raise ActiveRecord::RecordNotFound unless visible?(st.staff_profile)
        render json: statement_json(st, detail: true)
      end

      # FRS §4 / §8 — the quantity-and-earnings table.
      def report
        staff = StaffProfile.find(params.require(:staff_profile_id))
        raise ActiveRecord::RecordNotFound unless visible?(staff)
        from, to = resolve_range
        render json: Reporting::StaffEarnings.call(staff_profile: staff, from:, to:)
      end

      def lines
        staff = StaffProfile.find(params.require(:staff_profile_id))
        raise ActiveRecord::RecordNotFound unless visible?(staff)
        from, to = resolve_range
        rows = EarningLine.where(staff_profile_id: staff.id).in_period(from, to)
                          .order(:service_date, :id)
        render json: { lines: rows.map { |l| line_json(l) } }
      end

      # FRS §4: the Owner may add sessions and tips by hand.
      def create_line
        staff = StaffProfile.find(params.require(:staff_profile_id))
        line = Earnings::AddManualLine.call(
          staff_profile: staff, service_date: params.require(:service_date),
          actor: current_user, duration_minutes: params[:duration_minutes],
          quantity: params[:quantity] || 1, amount_cents: params[:amount_cents],
          note: params[:note]
        )
        render json: line_json(line), status: :created
      rescue Earnings::AddManualLine::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def create_adjustment
        st = EarningStatement.find(params[:id])
        return render json: { error: { code: "period_locked" } }, status: :unprocessable_content if st.earning_period.locked?

        EarningAdjustment.create!(
          earning_statement: st, service_date: params.require(:service_date),
          amount_cents: params.require(:amount_cents), reason: params.require(:reason),
          created_by_user: current_user
        )
        Earnings::BuildStatements.call(period: st.earning_period)
        render json: statement_json(st.reload, detail: true)
      end

      # Owner, or the therapist reading their own — a statement is pay data.
      def statement_pdf
        statement = EarningStatement.includes(:staff_profile, :earning_period).find(params[:id])
        unless current_user.owner? || current_user.staff_profile&.id == statement.staff_profile_id
          return render_forbidden
        end

        send_data Documents::EarningStatementPdf.call(statement:),
                  filename: "statement-#{statement.id}.pdf", type: "application/pdf",
                  disposition: "inline"
      end

      private

      def visible?(staff)
        current_user.owner? || current_user.staff_profile&.id == staff.id
      end

      def resolve_range
        if params[:from].present?
          [ Date.parse(params[:from]), Date.parse(params[:to] || params[:from]) ]
        else
          EarningPeriod.semi_monthly_bounds(default_business_date)
        end
      end

      # The salon's business day, not UTC's — see Location#today.
      def default_business_date
        Location.find_by(id: current_user.accessible_location_ids.first)&.today || Date.current
      end

      def period_json(period, statements: false)
        json = {
          id: period.id, starts_on: period.starts_on, ends_on: period.ends_on,
          kind: period.kind, status: period.status, locked: period.locked?
        }
        if statements
          json[:statements] = period.earning_statements
                                    .includes(:staff_profile).order("staff_profiles.display_name")
                                    .map { |s| statement_json(s) }
        end
        json
      end

      def statement_json(st, detail: false)
        json = {
          id: st.id, staff_profile_id: st.staff_profile_id,
          display_name: st.staff_profile.display_name,
          total_sessions: st.total_sessions,
          service_earnings_cents: st.service_earnings_cents,
          tips_cents: st.tips_cents, adjustments_cents: st.adjustments_cents,
          gross_amount_cents: st.gross_amount_cents,
          locked: st.earning_period.locked?
        }
        if detail
          json[:period] = { from: st.earning_period.starts_on, to: st.earning_period.ends_on }
          json[:breakdown] = Reporting::StaffEarnings.call(
            staff_profile: st.staff_profile,
            from: st.earning_period.starts_on, to: st.earning_period.ends_on
          )
          json[:adjustments] = st.earning_adjustments.map { |a|
            { id: a.id, service_date: a.service_date, amount_cents: a.amount_cents, reason: a.reason }
          }
        end
        json
      end

      def line_json(line)
        {
          id: line.id, service_date: line.service_date, source: line.source,
          duration_minutes: line.duration_minutes, quantity: line.quantity,
          rate_cents: line.rate_cents, amount_cents: line.amount_cents,
          appointment_id: line.appointment_id,
          # BR-33: what a combined session absorbed, so a statement is explainable.
          covers_item_ids: line.covers_item_ids,
          note: line.note
        }
      end
    end
  end
end
