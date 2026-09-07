# frozen_string_literal: true

# https://ddnexus.github.io/pagy/toolbox/configuration/initializer/

Pagy::OPTIONS[:limit] = 20
Pagy::OPTIONS[:slots] = 7
Pagy::OPTIONS[:data_keys] = %i[count page pages limit]

Pagy::OPTIONS.freeze
