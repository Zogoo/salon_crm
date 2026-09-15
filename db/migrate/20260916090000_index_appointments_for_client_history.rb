# The client directory sorts and filters by each client's last completed visit,
# worked out from appointments. With thousands of clients that lookup must be an
# index seek, not a scan of every appointment.
class IndexAppointmentsForClientHistory < ActiveRecord::Migration[8.1]
  def change
    add_index :appointments, %i[client_id status starts_at], name: "idx_appointments_client_status_start"
  end
end
