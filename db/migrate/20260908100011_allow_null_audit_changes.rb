class AllowNullAuditChanges < ActiveRecord::Migration[8.1]
  # Rails' `serialize ..., type: Hash` treats an empty hash as the type's
  # default and writes NULL, so a NOT NULL column rejected every audit row that
  # carried no changes — which is most reads. That broke care-note reads
  # entirely, and read logging is the only way to answer "who looked at this"
  # (doc 04 §5). Reads coerce NULL back to {}.
  def change
    change_column_null :audit_logs, :changes_json, true
    change_column_default :audit_logs, :changes_json, from: "{}", to: nil
  end
end
