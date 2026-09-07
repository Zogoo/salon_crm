require "rails_helper"

RSpec.describe "Api::V1::Notes", type: :request do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  describe "GET /api/v1/notes" do
    it "returns only the current user's notes with pagination meta" do
      create(:note, user: user, title: "Mine")
      create(:note, user: other, title: "Theirs")

      get "/api/v1/notes", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      titles = response.parsed_body["notes"].map { |n| n["title"] }
      expect(titles).to eq([ "Mine" ])
      expect(response.parsed_body["meta"]).to include("count", "page", "pages", "limit")
    end

    it "requires authentication" do
      get "/api/v1/notes"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/notes" do
    it "creates a note for the current user" do
      expect {
        post "/api/v1/notes", params: { note: { title: "New", body: "Body" } }, headers: auth_headers(user), as: :json
      }.to change(user.notes, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "rejects a note without a title" do
      post "/api/v1/notes", params: { note: { body: "No title" } }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/notes/:id" do
    it "updates the note" do
      note = create(:note, user: user)
      patch "/api/v1/notes/#{note.id}", params: { note: { title: "Renamed" } }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(note.reload.title).to eq("Renamed")
    end

    it "cannot touch another user's note" do
      note = create(:note, user: other)
      patch "/api/v1/notes/#{note.id}", params: { note: { title: "Hacked" } }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/notes/:id" do
    it "deletes the note" do
      note = create(:note, user: user)
      expect {
        delete "/api/v1/notes/#{note.id}", headers: auth_headers(user)
      }.to change(user.notes, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
