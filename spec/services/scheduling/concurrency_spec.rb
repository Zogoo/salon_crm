require "rails_helper"

# Doc 03 §6.1 test 1, and doc 08 §2.
#
# This is the single most important spec in the suite. Under PostgreSQL an
# EXCLUDE constraint made double-booking impossible at the storage layer. On
# SQLite that guarantee is application code inside BEGIN IMMEDIATE, so *this
# test is the guarantee*. If it is ever deleted, skipped or made lenient, the
# system has no protection against double-booking left.
RSpec.describe "Concurrent booking", type: :model do
  # Real threads need real connections, so transactional fixtures are off here
  # and the tables are cleaned by hand.
  self.use_transactional_tests = false

  # Real threads need real connections, so transactional fixtures are off and
  # the tables are cleaned by hand. DatabaseCleaner works out the delete order,
  # which hand-written lists stopped doing once orders, notifications and
  # earning lines gained foreign keys to appointments.
  before { DatabaseCleaner.strategy = :deletion }
  after  { DatabaseCleaner.clean }

  def attempt(world, threads:)
    results = Queue.new

    workers = Array.new(threads) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            appt = Scheduling::BookAppointment.call(
              location: world[:location], client: world[:client],
              variant_ids: [ world[:variant].id ], start_at: world[:at]
            )
            results << [ :ok, appt.id ]
          rescue Scheduling::BookAppointment::Conflict => e
            results << [ :conflict, e.message ]
          rescue => e
            results << [ :error, "#{e.class}: #{e.message}" ]
          end
        end
      end
    end
    workers.each(&:join)
    Array.new(results.size) { results.pop }
  end

  it "lets exactly one of 8 threads book the same slot" do
    world = build_world(rooms: { single: 1 }, therapists: 8)

    outcomes = attempt(world, threads: 8)
    ok = outcomes.count { |(status, _)| status == :ok }
    errors = outcomes.select { |(status, _)| status == :error }

    expect(errors).to be_empty, "unexpected errors: #{errors.inspect}"
    expect(ok).to eq(1)
    expect(Appointment.count).to eq(1)
    expect(AppointmentStaff.count).to eq(1)
  end

  it "lets exactly one thread take the last free therapist" do
    # Two rooms but one therapist: the room is not the scarce resource here,
    # so this exercises the therapist branch of the check rather than the room.
    world = build_world(rooms: { single: 4 }, therapists: 1)

    outcomes = attempt(world, threads: 6)
    ok = outcomes.count { |(status, _)| status == :ok }
    errors = outcomes.select { |(status, _)| status == :error }

    expect(errors).to be_empty, "unexpected errors: #{errors.inspect}"
    expect(ok).to eq(1)
    expect(Appointment.count).to eq(1)
  end

  it "opens transactions in IMMEDIATE mode, which is what makes the above safe" do
    mode = ActiveRecord::Base.connection
                             .instance_variable_get(:@connection_parameters)
                             &.dig(:default_transaction_mode)
    expect(mode.to_s).to eq("immediate"),
      "SQLite transactions are not IMMEDIATE — the booking race is open again (doc 08 §2)"
  end
end
