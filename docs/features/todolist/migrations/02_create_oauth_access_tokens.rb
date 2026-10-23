# Expand: new table for access and refresh token rows, one pair per sign-in (ADR-0003, ADR-0006).
# token and refresh_token hold hashes, never the plain secrets.
class CreateOauthAccessTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, null: false, foreign_key: { to_table: :users }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.string :previous_refresh_token, null: false, default: ''
      t.integer :expires_in
      t.string :scopes
      t.datetime :revoked_at

      t.datetime :created_at, null: false
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
