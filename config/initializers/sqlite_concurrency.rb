# Asserts the one SQLite behaviour the booking guarantee depends on.
#
# Doc 08 §2 / ADR-17: with no Postgres exclusion constraint, double-booking is
# prevented by a conflict check followed by an insert in
# Scheduling::BookAppointment. That pair is only safe if the write lock is held
# before the check runs — i.e. BEGIN IMMEDIATE rather than BEGIN DEFERRED.
#
# Rails 8.1's SQLite3 adapter does this by default, and also applies WAL,
# synchronous=normal and foreign_keys to every connection (DEFAULT_PRAGMAS), so
# there is nothing to configure here. But it is an invisible default: if a
# future Rails changes it, the race reopens with no failing test to catch it.
# So assert it at boot and fail loudly instead.
Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection_db_config.adapter.to_s.include?("sqlite")

  begin
    mode = ActiveRecord::Base.connection
                             .instance_variable_get(:@connection_parameters)
                             &.dig(:default_transaction_mode)
    if mode.to_s != "immediate"
      raise "SQLite default_transaction_mode is #{mode.inspect}, expected :immediate. " \
            "Booking conflict prevention depends on BEGIN IMMEDIATE — see doc 08 §2."
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    # db:create runs before the database exists.
  end
end
