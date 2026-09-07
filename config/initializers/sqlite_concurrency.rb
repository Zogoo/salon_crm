# SQLite concurrency settings — doc 08 §2, ADR-17.
#
# The architecture originally prevented double-booking with Postgres
# `EXCLUDE USING gist` constraints. SQLite has none, so conflict prevention
# lives in Scheduling::BookAppointment instead. That is only safe because
# SQLite serialises writers — and only if the write lock is already held when
# the conflict check runs, which BEGIN IMMEDIATE guarantees.
#
# WAL keeps readers from blocking on the writer; busy_timeout makes a contended
# writer wait rather than fail instantly.
Rails.application.config.after_initialize do
  ActiveSupport.on_load(:active_record) do
    next unless connection_db_config.adapter.to_s.include?("sqlite")

    ActiveRecord::Base.connection_pool.with_connection do |conn|
      conn.execute("PRAGMA journal_mode = WAL")
      conn.execute("PRAGMA busy_timeout = 5000")
      conn.execute("PRAGMA foreign_keys = ON")
      conn.execute("PRAGMA synchronous = NORMAL")

      # Rails 8.1 opens every SQLite transaction with BEGIN IMMEDIATE. The
      # booking guarantee depends on that, and it is an invisible default, so
      # assert it rather than trust it — a silent change here would reintroduce
      # the double-booking race with no failing test to catch it.
      mode = conn.instance_variable_get(:@connection_parameters)&.dig(:default_transaction_mode)
      if mode.to_s != "immediate" && !Rails.env.test?
        raise "SQLite default_transaction_mode is #{mode.inspect}, expected :immediate. " \
              "Booking conflict prevention depends on BEGIN IMMEDIATE — see doc 08 §2."
      end
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    # db:create / db:prepare runs before the database exists.
  end
end
