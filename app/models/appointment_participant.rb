class AppointmentParticipant < ApplicationRecord
  belongs_to :appointment
  belongs_to :client
end
