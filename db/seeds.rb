# Idempotent seed data for local development.
# Run with: bin/rails db:seed
#
# `db:prepare` runs this automatically on a freshly created database — including
# on the production boot in bin/docker-entrypoint — so the demo account must
# never be created outside development.
if Rails.env.production?
  puts "Skipping demo seeds in production."
else
  user = User.find_or_create_by!(email: "demo@mongolianmassagelab.com") do |u|
    u.name = "Demo User"
    u.password = "password123"
    u.password_confirmation = "password123"
  end

  if user.notes.none?
    user.notes.create!(title: "Welcome", body: "This is your first note. Edit or delete it.")
    user.notes.create!(title: "Getting started", body: "Sign in with demo@mongolianmassagelab.com / password123.")
  end

  puts "Seeded #{User.count} user(s) and #{Note.count} note(s)."
end
