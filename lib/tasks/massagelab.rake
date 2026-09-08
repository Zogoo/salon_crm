# Scheduled work, without a scheduler.
#
# The stack has no Sidekiq and no cron (doc 04 §8 assumed one; the scaffold
# uses Active Job's :async adapter). Rather than add a dependency, each job is
# a plain class and this task runs the ones that are due. Point the host's cron
# — or Fly's scheduled machines — at `rake massagelab:tick` every 15 minutes
# and `massagelab:nightly` once a day.
namespace :massagelab do
  desc "Frequent work: notifications, auto-approvals, no-show candidates"
  task tick: :environment do
    SendNotificationsJob.new.perform
    AutoApproveTherapistRequestsJob.new.perform
    candidates = MarkNoShowsJob.new.perform
    puts "no-show candidates for review: #{candidates.size}"
  end

  desc "Nightly work: expiry, reconciliation, drift checks"
  task nightly: :environment do
    result = NightlyMaintenanceJob.new.perform
    puts "gift cards flagged expired: #{result[:gift_cards_expired]}"
    %i[gift_card_drift membership_credit_drift appointment_staff_drift].each do |key|
      rows = result[key]
      puts rows.any? ? "DRIFT #{key}: #{rows.inspect}" : "#{key}: clean"
    end
  end

  desc "Open the current earnings period and close the previous"
  task open_period: :environment do
    period = OpenEarningPeriodsJob.new.perform
    puts "current period: #{period.starts_on} → #{period.ends_on} (#{period.status})"
  end
end
