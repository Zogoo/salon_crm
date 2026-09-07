module Api
  module V1
    class NotesController < ApplicationController
      include Pagy::Method

      def index
        scope = NotesQuery.new(current_user.notes).call(search: params[:search])
        pagy, records = pagy(scope)
        render json: { notes: records.map { |n| note_json(n) }, meta: pagy.data_hash }
      end

      def show
        render json: note_json(current_user.notes.find(params[:id]))
      end

      def create
        note = current_user.notes.new(note_params)
        if note.save
          render json: note_json(note), status: :created
        else
          render json: { error: note.errors.full_messages }, status: :unprocessable_content
        end
      end

      def update
        note = current_user.notes.find(params[:id])
        if note.update(note_params)
          render json: note_json(note)
        else
          render json: { error: note.errors.full_messages }, status: :unprocessable_content
        end
      end

      def destroy
        current_user.notes.find(params[:id]).destroy!
        head :no_content
      end

      private

      def note_params
        params.require(:note).permit(:title, :body)
      end

      def note_json(note)
        {
          id: note.id,
          title: note.title,
          body: note.body,
          created_at: note.created_at,
          updated_at: note.updated_at
        }
      end
    end
  end
end
