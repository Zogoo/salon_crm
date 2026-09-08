# Delivers whatever is due. Reminders are scheduled ahead (24 h and 2 h), so
# this is what actually releases them at the right moment.
class SendNotificationsJob < ApplicationJob
  def perform(now: Time.current)
    Notification.due(now).find_each do |notification|
      Notifications::Deliver.call(notification:, now:)
    end
  end
end
