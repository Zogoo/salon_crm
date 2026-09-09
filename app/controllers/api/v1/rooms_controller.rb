module Api
  module V1
    # Rooms belong to a location; their capacity and type drive C7/C9/C11 in the
    # scheduling engine, so editing one changes what can be booked.
    class RoomsController < ApplicationController
      # Reached as /locations/:id/rooms, where the location is :id.
      def index
        location = scoped_location!(params[:location_id] || params.require(:id))
        render json: { rooms: location.rooms.order(:position, :id).map { |r| room_json(r) } }
      end

      def create
        require_owner!
        location = scoped_location!(params.require(:location_id))
        room = location.rooms.create!(room_params)
        render json: room_json(room), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def update
        require_owner!
        room = find_room!
        room.update!(room_params)
        render json: room_json(room.reload)
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      # --- time-bounded unavailability (doc 02 §3.2) ---

      def blocks
        room = find_room!
        scope = room.room_blocks.order(:starts_at)
        scope = scope.where("ends_at >= ?", Time.current) unless params[:include_past] == "true"
        render json: { room_id: room.id, blocks: scope.map { |b| block_json(b, room) } }
      end

      def create_block
        room = find_room!
        tz = room.location.tz
        block = room.room_blocks.new(
          starts_at: tz.parse(params.require(:starts_at)),
          ends_at: tz.parse(params.require(:ends_at)),
          reason: params[:reason], created_by_user: current_user
        )
        # BR-07 in spirit: a block removes availability, so it must not land on
        # top of an appointment already in that room.
        clashes = Appointment.active.overlapping(block.starts_at, block.ends_at).where(room_id: room.id)
        if clashes.exists?
          return render json: { error: { code: "block_has_appointments",
                                         details: { appointment_ids: clashes.pluck(:id) } } },
                        status: :unprocessable_content
        end

        block.save!
        render json: block_json(block, room), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def destroy_block
        room = find_room!
        room.room_blocks.find(params[:block_id]).destroy!
        head :no_content
      end

      private

      def find_room!
        room = Room.includes(:location).find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(room.location_id)
        room
      end

      def room_params
        params.require(:room).permit(:name, :room_type, :client_capacity, :exclusive,
                                     :position, :status)
      end

      def room_json(room)
        { id: room.id, name: room.name, room_type: room.room_type,
          client_capacity: room.client_capacity, exclusive: room.exclusive,
          position: room.position, status: room.status, location_id: room.location_id }
      end

      def block_json(block, room)
        { id: block.id, starts_at: local_iso(block.starts_at, room.location),
          ends_at: local_iso(block.ends_at, room.location), reason: block.reason }
      end
    end
  end
end
