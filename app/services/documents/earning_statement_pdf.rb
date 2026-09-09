module Documents
  # Doc 05 §"Earnings": the therapist's statement for a period.
  #
  # BR-24a: tips are shown separately and in full, because none of the tip is
  # the salon's. BR-37: a locked period is immutable, and the statement says so
  # rather than leaving the reader to guess whether it can still move.
  class EarningStatementPdf < ApplicationService
    def initialize(statement:)
      @statement = statement
    end

    def call
      pdf = Prawn::Document.new(page_size: "A4", margin: 40)
      header(pdf)
      lines(pdf)
      totals(pdf)
      pdf.render
    end

    private

    def profile = @statement.staff_profile
    def period  = @statement.earning_period

    def header(pdf)
      pdf.text "Earnings statement", size: 16, style: :bold
      pdf.text profile.display_name, size: 12
      pdf.text "Period #{period.starts_on} to #{period.ends_on}", size: 10
      pdf.text(period.locked? ? "Locked — final" : "Draft — may still change", size: 9, style: :italic)
      pdf.move_down 14
    end

    def lines(pdf)
      rows = [ [ "Date", "Appointment", "Minutes", "Amount" ] ]
      earning_lines.each do |line|
        rows << [
          line.service_date.to_s, line.appointment_id.to_s,
          line.duration_minutes.to_s, money(line.amount_cents)
        ]
      end
      rows << [ "No lines in this period", "", "", "" ] if earning_lines.empty?

      pdf.table(rows, header: true, width: pdf.bounds.width,
                cell_style: { size: 9, borders: %i[bottom], padding: [ 4, 2 ] })
      pdf.move_down 10
    end

    def totals(pdf)
      pdf.text "Sessions (#{@statement.total_sessions}): #{money(@statement.service_earnings_cents)}", size: 10
      pdf.text "Tips: #{money(@statement.tips_cents)}", size: 10
      pdf.text "Adjustments: #{money(@statement.adjustments_cents)}", size: 10
      pdf.text "Total: #{money(@statement.gross_amount_cents)}", size: 12, style: :bold
    end

    def earning_lines
      @earning_lines ||= EarningLine.where(staff_profile: profile,
                                           service_date: period.starts_on..period.ends_on)
                                    .order(:earned_on, :id).to_a
    end

    def money(cents) = format("$%.2f", cents.to_i / 100.0)
  end
end
