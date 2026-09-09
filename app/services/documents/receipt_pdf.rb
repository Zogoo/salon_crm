module Documents
  # Doc 05 §"Money": a printable receipt for an order.
  #
  # BR-48 governs the layout as much as the reports do — service revenue, gift
  # card and membership liabilities, and fees are shown as separate lines and
  # never summed into a single "sales" figure.
  class ReceiptPdf < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      pdf = Prawn::Document.new(page_size: "A4", margin: 40)
      header(pdf)
      lines(pdf)
      totals(pdf)
      payments(pdf)
      pdf.render
    end

    private

    def location = @order.location

    def header(pdf)
      pdf.text location.name, size: 16, style: :bold
      pdf.text "Receipt #{@order.number}", size: 11
      pdf.text "Issued #{@order.created_at.in_time_zone(location.tz).strftime('%d %b %Y %H:%M')}", size: 9
      pdf.text "Client: #{@order.client&.full_name || 'Walk-in'}", size: 9
      pdf.move_down 14
    end

    def lines(pdf)
      rows = [ %w[Item Qty Amount] ]
      @order.order_line_items.order(:id).each do |item|
        rows << [ item.description, item.quantity.to_s, money(item.line_total_cents) ]
      end
      @order.order_discounts.each do |d|
        rows << [ "Discount — #{d.reason.presence || d.kind}", "", "-#{money(d.amount_cents)}" ]
      end
      pdf.table(rows, header: true, width: pdf.bounds.width,
                cell_style: { size: 9, borders: %i[bottom], padding: [ 4, 2 ] })
      pdf.move_down 10
    end

    def totals(pdf)
      pdf.text "Subtotal: #{money(@order.subtotal_cents)}", size: 10
      pdf.text "Tip (100% to the therapist): #{money(@order.tip_cents)}", size: 10
      pdf.text "Total: #{money(@order.total_cents)}", size: 12, style: :bold
    end

    def payments(pdf)
      pdf.move_down 10
      pdf.text "Payments", size: 10, style: :bold
      @order.payments.captured.each do |p|
        pdf.text "#{p.method.humanize}: #{money(p.amount_cents)}", size: 9
      end
      refunded = Refund.where(order: @order).sum(:amount_cents)
      pdf.text "Refunded: #{money(refunded)}", size: 9 if refunded.positive?
    end

    def money(cents) = format("$%.2f", cents.to_i / 100.0)
  end
end
