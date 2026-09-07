module Sales
  # BR-24 / BR-24a: the tip is the therapist's, in full. Two therapists split it
  # evenly unless the Manager overrides. It never reaches revenue.
  class AllocateTips < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, amount_cents:, allocations: nil, actor: nil)
      @order = order
      @amount = amount_cents.to_i
      @allocations = allocations
      @actor = actor
    end

    def call
      raise Invalid, "tip cannot be negative" if @amount.negative?

      ImmediateTransaction.call do
        @order.tip_allocations.destroy_all
        rows = @allocations.presence || even_split
        total = rows.sum { |r| r[:amount_cents].to_i }
        raise Invalid, "allocations must sum to the tip" unless total == @amount

        rows.each do |row|
          TipAllocation.create!(
            order: @order, appointment: @order.appointment,
            staff_profile_id: row[:staff_profile_id],
            amount_cents: row[:amount_cents],
            allocated_by: @allocations ? "manual" : "system_even_split"
          )
        end
        @order.recalculate!
      end
    end

    private

    def even_split
      staff = @order.appointment&.staff_profiles.to_a
      raise Invalid, "no therapist to tip" if staff.empty?
      return [] if @amount.zero?

      base = @amount / staff.size
      # The remainder goes to the primary therapist rather than vanishing.
      remainder = @amount - (base * staff.size)
      staff.each_with_index.map do |sp, i|
        { staff_profile_id: sp.id, amount_cents: base + (i.zero? ? remainder : 0) }
      end
    end
  end
end
