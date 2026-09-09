module Workforce
  # BR-35: a rate is never edited in place. Earnings use the rate that applied
  # on the *service date*, so mutating a row would silently restate pay for work
  # already done. A new rate closes the open period the day before it starts.
  #
  # Shared by the session ladder and the manager's monthly rate, which differ
  # only in what they write.
  module EffectiveDating
    module_function

    # Only periods already open *before* the new start are closed, so a
    # future-dated rate leaves today's rate in force until it takes over.
    def close_open_periods!(scope, effective_from)
      scope.where(effective_to: nil)
           .where("effective_from < ?", effective_from)
           .find_each { |row| row.update!(effective_to: effective_from - 1.day) }
    end
  end
end
