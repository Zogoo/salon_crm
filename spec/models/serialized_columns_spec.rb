require "rails_helper"

# A guard for a whole class of bug rather than one instance of it.
#
# Rails writes NULL for a serialized empty Array or Hash — it treats the empty
# value as the type's default and skips the dump entirely. Any such column that
# is NOT NULL therefore rejects its first legitimately-empty value, at runtime,
# in production. This already broke tip earning lines and care-note read
# logging before the pattern was recognised.
#
# This spec walks every serialized attribute in the app, so a new one cannot
# reintroduce it without failing here.
RSpec.describe "Serialized columns" do
  # Model => attribute names carrying a serialize coder.
  def serialized_attributes
    Rails.application.eager_load!
    ApplicationRecord.descendants.flat_map do |model|
      next [] unless model.table_exists?

      model.attribute_types.filter_map do |name, type|
        [ model, name ] if type.is_a?(ActiveRecord::Type::Serialized)
      end
    end
  end

  it "finds the serialized attributes it is meant to be guarding" do
    expect(serialized_attributes).not_to be_empty
  end

  it "never marks a serialized column NOT NULL" do
    offenders = serialized_attributes.filter_map do |model, name|
      column = model.columns_hash[name]
      next if column.nil? || column.null

      "#{model.table_name}.#{name}"
    end

    expect(offenders).to be_empty, <<~MSG
      These serialized columns are NOT NULL:

        #{offenders.join("\n  ")}

      Rails writes NULL for an empty Array or Hash, so the first empty value
      will raise NotNullViolation at runtime. Make the column nullable — the
      reader coerces NULL back to the empty value.
    MSG
  end

  it "round-trips an empty value through every serialized attribute" do
    failures = serialized_attributes.filter_map do |model, name|
      column = model.columns_hash[name]
      empty = model.type_for_attribute(name).deserialize(nil)

      record = model.new(name => empty)
      "#{model.table_name}.#{name}" if record.read_attribute(name).nil? && !column.null
    end

    expect(failures).to be_empty
  end
end
