# Runs a block inside a SQLite `BEGIN IMMEDIATE` transaction.
#
# Why this matters (doc 08 §2, ADR-17): with no Postgres exclusion constraint,
# double-booking is prevented by a conflict check followed by an INSERT. That
# pair is only safe if the write lock is already held when the check runs. A
# deferred transaction takes the lock lazily, on first write, leaving exactly
# the race the constraint used to close.
#
# Rails 8.1's SQLite3 adapter already opens every transaction with
# BEGIN IMMEDIATE (`default_transaction_mode: :immediate`), so this wrapper is
# a plain transaction plus a name that says what it depends on. The boot check
# in config/initializers/sqlite_concurrency.rb asserts that default, so if a
# future Rails changes it the app fails loudly instead of silently losing the
# guarantee.
module ImmediateTransaction
  module_function

  def call(&block)
    # `requires_new: true` gives a real transaction at the top level and a
    # SAVEPOINT when nested. A nested call could simply join the outer
    # transaction — it already holds the lock — but then a service would not be
    # a rollback boundary of its own, and any caller that rescued between the
    # two would keep its partial writes. The savepoint does not release the
    # write lock, so the guarantee above is unaffected.
    ActiveRecord::Base.transaction(requires_new: true, &block)
  end
end
