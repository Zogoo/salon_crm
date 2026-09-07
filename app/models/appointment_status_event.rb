class AppointmentStatusEvent < ApplicationRecord
  belongs_to :appointment
  belongs_to :actor_user, class_name: "User", optional: true
end
