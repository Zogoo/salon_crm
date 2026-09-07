# Column-level encryption for care notes and the client preferences form
# (doc 04 §5). Keys come from the environment so a database dump alone is not a
# breach — they are never committed and never stored beside the data.
#
# Development and test fall back to fixed values so the stack boots with no
# setup; production has no fallback and will refuse to start without real keys.
Rails.application.configure do
  fallback = Rails.env.local? ? "dev-only-not-a-secret-0000000000000000" : nil

  config.active_record.encryption.primary_key =
    ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY", fallback)
  config.active_record.encryption.deterministic_key =
    ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY", fallback && "#{fallback}-det")
  config.active_record.encryption.key_derivation_salt =
    ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT", fallback && "#{fallback}-salt")

  # Existing rows written before encryption was switched on stay readable.
  config.active_record.encryption.support_unencrypted_data = true
end
