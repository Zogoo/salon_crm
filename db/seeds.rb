# Idempotent seed. Safe to re-run; every record is found-or-created.
require_relative "seeds/catalogue"
require_relative "seeds/people"

locations = Seeds::Catalogue.seed!
Seeds::People.seed!(locations)

puts <<~SUMMARY
  Seeded:
    locations      #{Location.count}
    rooms          #{Room.count}
    services       #{Service.count} (#{Service.payable.count} payable)
    variants       #{ServiceVariant.count}
    location prices #{LocationPrice.count}
    users          #{User.count} (#{User.where(role: 'owner').count} owner, #{User.where(role: 'manager').count} manager, #{User.where(role: 'staff').count} staff)
    therapists     #{StaffProfile.count}
    shifts         #{Shift.count}
    clients        #{Client.count}

  Sign in with any of:
    owner@mongolianmassagelab.com      / password123
    manager.luma@mongolianmassagelab.com / password123
    anna.lawrence@mongolianmassagelab.com / password123
SUMMARY
