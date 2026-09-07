module Api
  module V1
    class ProfilesController < ApplicationController
      def show
        render json: user_json(current_user)
      end

      def update
        if current_user.update(profile_params)
          render json: user_json(current_user)
        else
          render json: { error: current_user.errors.full_messages }, status: :unprocessable_content
        end
      end

      def destroy_avatar
        current_user.avatar.purge if current_user.avatar.attached?
        render json: user_json(current_user)
      end

      private

      def profile_params
        params.permit(:name, :avatar)
      end
    end
  end
end
