# FRS §8: the two standing periods are the 1st–15th and the 16th–end of month.
# Opens the current one and closes the previous, so the Owner always has a
# period to look at without anyone creating it by hand.
class OpenEarningPeriodsJob < ApplicationJob
  def perform(now: Time.current)
    current = EarningPeriod.for_date(now.to_date)
    previous_end = current.starts_on - 1
    previous = EarningPeriod.find_by(
      **%i[starts_on ends_on].zip(EarningPeriod.semi_monthly_bounds(previous_end)).to_h
    )
    if previous && previous.status == "open"
      Earnings::BuildStatements.call(period: previous)
      previous.update!(status: "in_review")
    end
    Earnings::BuildStatements.call(period: current)
    current
  end
end
