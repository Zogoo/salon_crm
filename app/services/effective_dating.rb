# BR-35 (pay rates) and invariant 5 (prices): an effective-dated row is never
# edited in place.
#
# Earnings use the rate that applied on the *service date*, and an order uses
# the price that applied on the booking date, so mutating a row would silently
# restate history that has already been paid or invoiced. A new row closes the
# open period the day before it starts instead.
module EffectiveDating
  module_function

  # Only periods already open *before* the new start are closed, so a
  # future-dated row leaves today's in force until it takes over.
  def close_open_periods!(scope, effective_from)
    scope.where(effective_to: nil)
         .where("effective_from < ?", effective_from)
         .find_each { |row| row.update!(effective_to: effective_from - 1.day) }
  end
end
